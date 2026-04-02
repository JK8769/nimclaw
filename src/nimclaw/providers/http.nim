import std/[asyncdispatch, json, strutils, tables, os]
import curly, webby/httpheaders
import ../lib/malebolgia
import ../lib/http_retry
import types
import ../logger
from ../tools/registry import sanitizeToolName
import unicode

proc expandEnvVar(val: string): string =
  ## Expands ${VAR} using environment variables.
  if val.startsWith("${") and val.endsWith("}"):
    return getEnv(val[2..^2], val)
  return val

proc sanitizeUtf8(s: string): string =
  ## Ensure the string is valid UTF-8, replacing invalid segments with U+FFFD
  result = ""
  var i = 0
  while i < s.len:
    var length = runeLenAt(s, i)
    if length > 0:
      for _ in 1..length:
        result.add(s[i])
        inc i
    else:
      # Invalid sequence, append replacement character
      result.add("\uFFFD")
      inc i

type
  HTTPProvider* = ref object of LLMProvider
    apiKey*: string
    apiBase*: string
    defaultModel*: string
    curly*: Curly
    master*: Master
    timeout*: int

proc newHTTPProvider*(apiKey, apiBase, defaultModel: string, timeout: int): HTTPProvider =
  HTTPProvider(
    apiKey: apiKey,
    apiBase: apiBase,
    defaultModel: defaultModel,
    curly: newCurly(),
    master: createMaster(),
    timeout: timeout
  )

method getDefaultModel*(p: HTTPProvider): string =
  return p.defaultModel

method chat*(p: HTTPProvider, messages: seq[Message], tools: seq[ToolDefinition], model: string, options: Table[string, JsonNode]): Future[LLMResponse] {.async.} =
  if p.apiBase == "":
    raise newException(ValueError, "API base not configured")

  var actualModel = model
  # Only strip prefixes if we are hitting certain internal providers or if explicitly requested.
  # For many providers like NVIDIA/OpenRouter, the prefix IS part of the model ID.
  # We will only strip 'opencode/' prefixes for now as that's our legacy convention.
  if actualModel.startsWith("opencode/"):
    actualModel = actualModel.replace("opencode/", "")
  elif actualModel.startsWith("opencode-go/"):
    actualModel = actualModel.replace("opencode-go/", "")

  # We need to sanitize tool names in the history to avoid DeepSeek 400 errors
  # if previous calls used colons (like nc:submit).

  var jsonMessages = newJArray()
  for m in messages:
    var jMsg = %*{
      "role": m.role,
      "content": sanitizeUtf8(m.content)
    }
    if m.reasoning_content != "":
      jMsg["reasoning_content"] = %sanitizeUtf8(m.reasoning_content)
    if m.role == "tool":
      jMsg["tool_call_id"] = %m.tool_call_id
      if m.name != "": jMsg["name"] = %sanitizeToolName(m.name)
    elif m.role == "assistant" and m.tool_calls.len > 0:
      var jCalls = newJArray()
      for tc in m.tool_calls:
        jCalls.add(%*{
          "id": tc.id,
          "type": tc.`type`,
          "function": %*{
            "name": sanitizeToolName(tc.function.name),
            "arguments": tc.function.arguments
          }
        })
      jMsg["tool_calls"] = jCalls
      if m.content == "": jMsg["content"] = %""
    jsonMessages.add(jMsg)

  var requestBody = %*{
    "model": actualModel,
    "messages": jsonMessages
  }

  if tools.len > 0 and not model.startsWith("opencode/") and not model.startsWith("opencode-go/"):
    requestBody["tools"] = %tools

  if options.hasKey("max_tokens"):
    let lowerModel = model.toLowerAscii
    if lowerModel.contains("glm") or lowerModel.contains("o1"):
      requestBody["max_completion_tokens"] = options["max_tokens"]
    else:
      requestBody["max_tokens"] = options["max_tokens"]

  if options.hasKey("temperature"):
    requestBody["temperature"] = options["temperature"]

  var headers = emptyHttpHeaders()
  headers["Content-Type"] = "application/json"
  headers["HTTP-Referer"] = "https://github.com/nimclaw/nimclaw"
  headers["X-Title"] = "Nimclaw"
  headers["User-Agent"] = "NimClaw/0.1.0"
  
  if p.apiKey != "":
    headers["Authorization"] = "Bearer " & p.apiKey

  let url = p.apiBase & "/chat/completions"
  
  # Mask API key for logging
  let maskedKey = if p.apiKey.len > 10: 
    p.apiKey[0..3] & "..." & p.apiKey[^4..^1] 
  else: 
    "***"
    
  infoCF("http_provider", "Sending LLM request (via curly)", {
    "url": url,
    "model": actualModel,
    "api_key_masked": maskedKey,
    "api_key_len": $p.apiKey.len
  }.toTable)

  if tools.len > 0:
    for t in tools:
      infoCF("http_provider", "Tool definition", {"name": t.function.name, "json": $(%t)}.toTable)
  
  debugCF("http_provider", "Full request body", {"json": $requestBody}.toTable)

  proc doRequest(c: Curly, url, body: string, headers: HttpHeaders, timeout: int): tuple[code: int, body: string] =
    curlyPostWithRetry(c, url, body, headers, timeout)

  # Instrumentation for opencode_go debugging
  if url.contains("/go/"):
    let maskedKey = if p.apiKey.len > 10: 
      p.apiKey[0..9] & "..."
    else: 
      "***"
    infoCF("http_provider", "Opencode Go Request Details", {
      "url": url,
      "apiKey_masked": maskedKey,
      "body": $requestBody
    }.toTable)

  let fv = p.master.spawn doRequest(p.curly, url, $requestBody, headers, p.timeout)
  
  # Busy-wait for TaskVar in an async-friendly way
  while not fv.isReady:
    await sleepAsync(10)
    
  let (code, body) = fv.sync()

  if code == -1:
    raise newException(IOError, "Curly request failed: " & body)

  if code < 200 or code >= 300:
    raise newException(IOError, "API error ($1): $2".format(code, body))

  let jsonResp = parseJson(body)

  var llmResp = LLMResponse()
  if jsonResp.hasKey("choices") and jsonResp["choices"].len > 0:
    let choice = jsonResp["choices"][0]
    let msg = choice["message"]
    if msg.hasKey("content") and msg["content"].kind != JNull:
      llmResp.content = msg["content"].getStr()
    
    if msg.hasKey("reasoning_content") and msg["reasoning_content"].kind != JNull:
      llmResp.reasoning_content = msg["reasoning_content"].getStr()

    if msg.hasKey("tool_calls"):
      for tc in msg["tool_calls"]:
        var toolCall = ToolCall(
          id: tc["id"].getStr(),
          `type`: tc.getOrDefault("type").getStr("function")
        )
        if tc.hasKey("function"):
          let fn = tc["function"]
          toolCall.name = fn["name"].getStr()
          let argsStr = fn["arguments"].getStr()
          try:
            let argsJson = parseJson(argsStr)
            for k, v in argsJson.fields:
              toolCall.arguments[k] = v
          except:
            toolCall.arguments["raw"] = %argsStr
        llmResp.tool_calls.add(toolCall)

    llmResp.finish_reason = choice.getOrDefault("finish_reason").getStr("stop")

  if jsonResp.hasKey("usage") and jsonResp["usage"].kind == JObject:
    let usage = jsonResp["usage"]
    llmResp.usage = UsageInfo(
      prompt_tokens: if usage.hasKey("prompt_tokens"): usage["prompt_tokens"].getInt() else: 0,
      completion_tokens: if usage.hasKey("completion_tokens"): usage["completion_tokens"].getInt() else: 0,
      total_tokens: if usage.hasKey("total_tokens"): usage["total_tokens"].getInt() else: 0
    )

  return llmResp

proc createProvider*(model, apiKey, apiBase: string, timeout: int = 300): LLMProvider =
  return newHTTPProvider(apiKey, apiBase, model, timeout)

const PROVIDER_BASE_URLS* = {
  "opencode": "https://opencode.ai/zen/go/v1",
  "opencode-go": "https://opencode.ai/zen/go/v1",
  "deepseek": "https://api.deepseek.com",
  "openai": "https://api.openai.com/v1",
  "anthropic": "https://api.anthropic.com/v1",
  "groq": "https://api.groq.com/openai/v1",
  "openrouter": "https://openrouter.ai/api/v1",
  "nvidia": "https://integrate.api.nvidia.com/v1",
}.toTable

proc resolveProviderTech*(cfg_model, cfg_default_provider: string, graph_providers: JsonNode, providerOverride: string = "", modelOverride: string = ""): tuple[model, apiKey, apiBase: string] =
  ## Resolves provider credentials from the world graph with fallback to known base URLs.
  result.model = cfg_model
  if modelOverride != "": result.model = modelOverride

  var providerKey = if providerOverride != "": providerOverride
    elif result.model.contains("/"): result.model.split("/")[0]
    else: cfg_default_provider

  if graph_providers != nil and graph_providers.kind == JObject and graph_providers.hasKey(providerKey):
    let pNode = graph_providers[providerKey]
    result.apiKey = expandEnvVar(pNode{"apiKey"}.getStr(""))
    result.apiBase = expandEnvVar(pNode{"apiBase"}.getStr(""))

  if result.apiBase == "" and PROVIDER_BASE_URLS.hasKey(providerKey):
    result.apiBase = PROVIDER_BASE_URLS[providerKey]
