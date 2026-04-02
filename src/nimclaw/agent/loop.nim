import std/[json, strutils, asyncdispatch, tables, locks, os, options]
import ../bus, ../bus_types, ../config, ../logger, ../providers/types as providers_types, ../session, ../utils
import context as agent_context
import xml_tools
import ../schema
import ../tools/registry as tools_registry
import ../tools/base as tools_base
import ../tools/[filesystem, edit, shell, spawn, subagent, web, message, reply, forward, remember, memory_store, memory_list, memory_recall, memory_forget, http_request, git, pushover, screenshot, image_info, composio, browser_open, hardware_info, hardware_memory, i2c, spi, delegate, cron, forge, list, persist, invite, query_graph, skill_install, config_tools, orchestrate, update_contact, jq, clock]
import ../services/cron as cron_service
import curly
import ../lib/malebolgia
import ../skills/installer as skills_installer
import ../skills/loader as skills_loader
import cortex, invites, times

type
  ActionType* = enum
    atStart = "start"
    atFinish = "finish"
    atCancel = "cancel"
    atInference = "inference"
    atToolCall = "tool_call"
    atStatus = "status"

  TaskContext* = ref object
    id*: string
    openedAt*: string
    tokensTotal*: int
    responseSent*: bool

type
  ProcessOptions* = object
    sessionKey*: string
    senderID*: string
    recipientID*: string
    channel*: string
    chatID*: string
    replyToMessageID*: string
    appID*: string
    userMessage*: string
    defaultResponse*: string
    enableSummary*: bool
    sendResponse*: bool
    userRole*: string
    streamIntermediary*: bool

  AgentLoop* = ref object
    cfg*: Config
    bus*: MessageBus
    provider*: LLMProvider
    workspace*: string
    officeDir*: string
    agentName*: string
    role*: string
    entity*: string
    identity*: string
    model*: string
    contextWindow*: int
    temperature*: float
    maxIterations*: int
    sessions*: SessionManager
    contextBuilder*: ContextBuilder
    tools*: ToolRegistry
    cronService*: CronService
    running*: bool
    summarizing*: Table[string, bool]
    summarizingLock*: Lock
    taskCounter*: int
    agentId*: string
    curly*: Curly  # shared HTTP client, closed in stop()

proc stop*(al: AgentLoop) =
  al.running = false
  if al.tools != nil:
    al.tools.stopAllMcpClients()
  if al.curly != nil:
    try: al.curly.close()
    except: discard

proc registerTool*(al: AgentLoop, tool: Tool) =
  al.tools.register(tool)

proc estimateTokens(messages: seq[providers_types.Message]): int =
  var total = 0
  for m in messages:
    total += m.content.len div 4
  return total

proc summarizeBatch(al: AgentLoop, batch: seq[providers_types.Message], existingSummary: string): Future[string] {.async.} =
  var prompt = "Provide a concise summary of this conversation segment, preserving core context and key points.\n"
  if existingSummary != "":
    prompt.add("Existing context: " & existingSummary & "\n")
  prompt.add("\nCONVERSATION:\n")
  for m in batch:
    prompt.add(m.role & ": " & m.content & "\n")

  let response = await al.provider.chat(@[providers_types.Message(role: "user", content: prompt)], @[], al.model, initTable[string, JsonNode]())
  return response.content

proc summarizeSession(al: AgentLoop, sessionKey: string) {.async.} =
  let history = al.sessions.getHistory(sessionKey)
  let summary = al.sessions.getSummary(sessionKey)

  if history.len <= 4: return
  let toSummarize = history[0 .. ^5]

  # Oversized Message Guard
  let maxMessageTokens = al.contextWindow div 2
  var validMessages: seq[providers_types.Message] = @[]
  for m in toSummarize:
    if m.role == "user" or m.role == "assistant":
      if (m.content.len div 4) < maxMessageTokens:
        validMessages.add(m)

  if validMessages.len == 0: return

  let finalSummary = await al.summarizeBatch(validMessages, summary)

  if finalSummary != "":
    al.sessions.setSummary(sessionKey, finalSummary)
    al.sessions.truncateHistory(sessionKey, 4)
    al.sessions.save(al.sessions.getOrCreate(sessionKey))

const MaxJournalSize = 1_000_000 # 1MB before rotation

proc appendJournal(al: AgentLoop, entry: JsonNode) =
  ## Append a JSON entry to activity.jsonl with size-based rotation.
  let journalPath = al.officeDir / "activity.jsonl"
  try:
    if fileExists(journalPath) and getFileSize(journalPath) > MaxJournalSize:
      let archivePath = al.officeDir / "activity.jsonl.1"
      try: removeFile(archivePath)
      except: discard
      moveFile(journalPath, archivePath)
    let f = open(journalPath, fmAppend)
    f.writeLine($entry)
    f.close()
  except: discard

proc updateSnapshot(al: AgentLoop, entry: JsonNode, remove: bool = false) =
  let snapshotPath = al.officeDir / "status.json"
  try:
    if remove: removeFile(snapshotPath)
    else: writeFile(snapshotPath, $entry)
  except: discard

proc logTaskHeader*(al: AgentLoop, ctx: TaskContext, action: ActionType) =
  let ts = now().format("yyyy-MM-dd'T'HH:mm:sszzz")
  if ctx.openedAt == "": ctx.openedAt = ts

  var entry = newJObject()
  entry["taskId"] = %ctx.id
  entry["ts"] = %ts
  entry["action"] = %($action)

  if action == atStart:
    entry["provider"] = %(if al.model.contains("/"): al.model.split("/")[0] else: "default")
    entry["model"] = %al.model
    entry["hostPid"] = %getCurrentProcessId()
  elif action == atFinish or action == atCancel:
    entry["tokensTotal"] = %ctx.tokensTotal

  al.appendJournal(entry)

  if action == atStart:
    al.updateSnapshot(entry)
  elif action == atFinish or action == atCancel:
    al.updateSnapshot(entry, remove = true)

proc logAction*(al: AgentLoop, ctx: TaskContext, action: ActionType, tokens: int = 0, metadata: JsonNode = newJObject()) =
  let ts = now().format("yyyy-MM-dd'T'HH:mm:sszzz")
  var entry = newJObject()
  entry["taskId"] = %ctx.id
  entry["ts"] = %ts
  entry["action"] = %($action)
  if tokens > 0: entry["tokens"] = %tokens

  for k, v in metadata.pairs:
    entry[k] = v

  al.appendJournal(entry)
  al.updateSnapshot(entry)

proc updateStatus*(al: AgentLoop, ctx: TaskContext, status: string, detail: string = "", iter: int = 0) =
  var meta = newJObject()
  meta["status"] = %status
  meta["detail"] = %detail
  if iter > 0: meta["iteration"] = %iter
  al.logAction(ctx, atStatus, 0, meta)


proc maybeSummarize(al: AgentLoop, sessionKey: string) =
  acquire(al.summarizingLock)
  if al.summarizing.hasKey(sessionKey) and al.summarizing[sessionKey]:
    release(al.summarizingLock)
    return

  let history = al.sessions.getHistory(sessionKey)
  let tokenEstimate = estimateTokens(history)
  let threshold = (al.contextWindow * 75) div 100

  if history.len > 20 or tokenEstimate > threshold:
    al.summarizing[sessionKey] = true
    release(al.summarizingLock)
    discard (proc() {.async.} =
      await summarizeSession(al, sessionKey)
      acquire(al.summarizingLock)
      al.summarizing[sessionKey] = false
      release(al.summarizingLock)
    )()
  else:
    release(al.summarizingLock)

proc isXmlToolProvider*(model: string): bool =
  ## Returns true for providers that need XML tool calling instead of native tools.
  model.startsWith("opencode/") or model.startsWith("opencode-go/")

proc buildToolContext(al: AgentLoop, opts: ProcessOptions, logicalUserID: string): tools_base.ToolContext =
  tools_base.ToolContext(
    channel: opts.channel,
    chatID: opts.chatID,
    sessionKey: opts.sessionKey,
    senderID: opts.senderID,
    recipientID: opts.recipientID,
    role: opts.userRole,
    agentName: al.agentName,
    agentID: al.agentId,
    logicalUserID: logicalUserID,
    appID: opts.appID,
    replyToMessageID: opts.replyToMessageID,
    graph: al.contextBuilder.graph,
    entity: al.entity,
    identity: al.identity
  )

proc runLLMIteration(al: AgentLoop, ctx: TaskContext, messages: seq[providers_types.Message], opts: ProcessOptions, logicalUserID: string): Future[(string, int, seq[providers_types.Message])] {.async.} =
  var iteration = 0
  var finalContent = ""
  var lastResponseContent = ""  # Track last response for loop exhaustion fallback
  var currentMessages = messages
  let useXmlTools = isXmlToolProvider(al.model)
  let toolCtx = buildToolContext(al, opts, logicalUserID)

  while iteration < al.maxIterations:
    iteration += 1
    al.updateStatus(ctx, "Thinking", "Running iteration", iteration)
    
    infoCF("agent", "LLM iteration", {"iteration": $iteration, "max": $al.maxIterations, "xml_tools": $useXmlTools, "messages_count": $currentMessages.len}.toTable)

    let strategy = inferStrategy(al.model)

    # Tool definitions are constant for the entire request — compute once
    if iteration == 1:
      infoCF("agent", "Getting tool definitions", {"strategy": $strategy, "available_tools": $al.tools.list()}.toTable)
    let toolDefs =
      if useXmlTools:
        @[]
      else:
        let roleLow = opts.userRole.toLowerAscii()
        if roleLow in ["guest", "customer"]:
          al.tools.getDefinitionsFiltered(strategy, @(tools_registry.ExternalAllowedTools))
        else:
          al.tools.getDefinitions(strategy)

    let options = {
      "max_tokens": %al.contextWindow,
      "temperature": %al.temperature
    }.toTable
    
    var response: LLMResponse
    try:
      response = await al.provider.chat(currentMessages, toolDefs, al.model, options)
    except Exception as e:
      errorCF("agent", "LLM API request failed", {"error": e.msg, "iteration": $iteration}.toTable)
      if finalContent == "":
        finalContent = "Error communicating with LLM provider: " & e.msg
      break

    # Accumulate tokens
    let tokens = response.usage.total_tokens
    ctx.tokensTotal += tokens
    
    var llmMeta = newJObject()
    llmMeta["iteration"] = %iteration
    if al.model != al.cfg.agents.defaults.model: llmMeta["model"] = %al.model
    al.logAction(ctx, atInference, tokens, llmMeta)
    
    # Track last response for fallback
    lastResponseContent = response.content
    infoCF("agent", "LLM response received", {"iteration": $iteration, "content_len": $response.content.len, "content_preview": truncate(response.content, 200)}.toTable)

    if useXmlTools:
      # XML tool calling path: parse <tool_call> tags from text response
      let xmlCalls = parseXmlToolCalls(response.content)

      if xmlCalls.len == 0:
        # No XML tool calls found — this is the final response
        if hasXmlToolCalls(response.content):
          warnCF("agent", "XML tags detected but parsing failed. Check JSON format.\nFull response:\n" & response.content, {"iteration": $iteration}.toTable)
        
        finalContent = response.content
        infoCF("agent", "LLM response without XML tool calls", {"iteration": $iteration}.toTable)
        break

      # Tool call telemetry
      var toolMeta = newJObject()
      var toolNames = newJArray()
      for tool in xmlCalls: toolNames.add(%tool.name)
      toolMeta["tools"] = toolNames
      toolMeta["iteration"] = %iteration
      al.logAction(ctx, atToolCall, 0, toolMeta)
      
      al.updateStatus(ctx, "Executing Tools", "Processing " & $xmlCalls.len & " tools", iteration)
      
      # Extract display text (text outside tool call tags)
      let displayText = extractTextFromResponse(response.content)
      if displayText.len > 0:
        infoCF("agent", "XML tool intermediary text: " & truncate(displayText, 120), {"iteration": $iteration}.toTable)
        if opts.streamIntermediary:
          al.bus.publishOutbound(newOutbound(opts.channel, opts.recipientID, opts.chatID, displayText, opts.replyToMessageID, opts.appID))

      # Save assistant message (with full content including tool call tags) to history
      let assistantMsg = providers_types.Message(role: "assistant", content: response.content, reasoning_content: response.reasoning_content)
      currentMessages.add(assistantMsg)
      al.sessions.addFullMessage(opts.sessionKey, assistantMsg)

      # Execute each XML tool call
      var xmlResults: seq[XmlToolResult] = @[]
      for xmlCall in xmlCalls:
        infoCF("agent", "XML Tool call: " & xmlCall.name, {"tool": xmlCall.name, "iteration": $iteration, "role": al.role}.toTable)
        if xmlCall.name == "reply" or xmlCall.name == "message":
          ctx.responseSent = true
        let result = await al.tools.executeWithContext(xmlCall.name, xmlCall.arguments, toolCtx)
        xmlResults.add(XmlToolResult(name: xmlCall.name, output: result, success: not result.startsWith("Error:")))

      # Format tool results and add as a user message
      let formattedResults = formatToolResults(xmlResults)
      let toolResultMsg = providers_types.Message(role: "user", content: formattedResults)
      currentMessages.add(toolResultMsg)
      al.sessions.addMessage(opts.sessionKey, "user", formattedResults)

    else:
      # Native tool calling path (unchanged)
      if response.tool_calls.len == 0:
        finalContent = response.content
        infoCF("agent", "LLM response without tool calls", {"iteration": $iteration}.toTable)
        break

      if opts.streamIntermediary and response.content.len > 0:
        al.bus.publishOutbound(newOutbound(opts.channel, opts.recipientID, opts.chatID, response.content, opts.replyToMessageID, opts.appID))

      var assistantMsg = providers_types.Message(role: "assistant", content: response.content, reasoning_content: response.reasoning_content, tool_calls: response.tool_calls)
      currentMessages.add(assistantMsg)
      al.sessions.addFullMessage(opts.sessionKey, assistantMsg)

      var toolMeta = newJObject()
      var toolNames = newJArray()
      for tc in response.tool_calls: toolNames.add(%tc.name)
      if toolNames.len > 0:
        toolMeta["tools"] = toolNames
        toolMeta["iteration"] = %iteration
        al.logAction(ctx, atToolCall, 0, toolMeta)
        al.updateStatus(ctx, "Executing Tools", "Processing " & $toolNames.len & " tools", iteration)

      for tc in response.tool_calls:
        infoCF("agent", "Tool call: " & tc.name, {"tool": tc.name, "iteration": $iteration, "role": al.role}.toTable)
        if tc.name == "reply" or tc.name == "message":
          ctx.responseSent = true
        let result = await al.tools.executeWithContext(tc.name, tc.arguments, toolCtx)
        let toolResultMsg = providers_types.Message(role: "tool", content: result, tool_call_id: tc.id, name: tc.name)
        currentMessages.add(toolResultMsg)
        al.sessions.addFullMessage(opts.sessionKey, toolResultMsg)

  # If loop exhausted maxIterations without breaking, make one final LLM call for summary
  if finalContent == "" and lastResponseContent != "":
    warnCF("agent", "Tool loop exhausted maxIterations without final response", {"iterations": $iteration, "max": $al.maxIterations}.toTable)
    
    # Always do a summary call — the last response was a tool call, not a real answer
    infoCF("agent", "Making final summary LLM call after loop exhaustion", initTable[string, string]())
    currentMessages.add(providers_types.Message(role: "user", content: "STOP using tools. You have reached the maximum number of tool iterations (" & $al.maxIterations & "). Provide your FINAL response to the user NOW. Summarize what you accomplished and any results from the tools you used. Do NOT call any more tools."))
    try:
      let toolDefs: seq[ToolDefinition] = @[]
      let summaryOpts = {"max_tokens": %4096, "temperature": %al.temperature}.toTable
      let summaryResp = await al.provider.chat(currentMessages, toolDefs, al.model, summaryOpts)
      if summaryResp.content.len > 0:
        let cleaned = extractTextFromResponse(summaryResp.content)
        finalContent = if cleaned.len > 0: cleaned else: summaryResp.content
    except Exception as e:
      errorCF("agent", "Final summary LLM call failed", {"error": e.msg}.toTable)
      # Fall back to extracted intermediary text
      let extracted = extractTextFromResponse(lastResponseContent)
      if extracted.len > 0:
        finalContent = extracted
  elif finalContent == "":
    warnCF("agent", "Tool loop ended with empty finalContent", {"iterations": $iteration}.toTable)

  return (finalContent, iteration, currentMessages)

proc runAgentLoop*(al: AgentLoop, optsParam: ProcessOptions): Future[string] {.async.} =
  var opts = optsParam
  if opts.userRole == "": opts.userRole = "Guest"
  
  let epochMs = int(getTime().toUnixFloat() * 1000)
  al.taskCounter += 1
  let taskId = al.agentId & ":" & $epochMs & ":" & align($al.taskCounter, 3, '0')
  
  let ctx = TaskContext(
    id: taskId,
    openedAt: "",
    tokensTotal: 0
  )
  
  al.logTaskHeader(ctx, atStart)
  
  try:
    let history = al.sessions.getHistory(opts.sessionKey)
    let summary = al.sessions.getSummary(opts.sessionKey)
    let useXmlTools = isXmlToolProvider(al.model)
    # Perform sentiment analysis and update mood
    let (vDelta, aDelta) = cortex.analyzeSentiment(opts.userMessage)
    cortex.updateMood(al.contextBuilder.mood, vDelta, aDelta)
    cortex.saveMood(al.workspace, al.contextBuilder.mood)

    # Resolve raw senderID to logical userID
    var logicalUserID = opts.senderID
    var isKnown = false
    
    var activeRecipient = opts.recipientID
    if activeRecipient == "": activeRecipient = al.agentName
    
    if al.contextBuilder.graph != nil:
      var agentId = WorldEntityID(0)
      if activeRecipient != "" and al.contextBuilder.graph.nameIndex.hasKey(activeRecipient):
        agentId = al.contextBuilder.graph.nameIndex[activeRecipient]
        
      let (resolvedID, annotOpt) = al.contextBuilder.graph.resolveUserGraph(opts.channel, opts.senderID, agentId)
      if uint32(resolvedID) > 0:
        logicalUserID = toAlias(resolvedID)
        isKnown = true
        
        # Calculate user role for tool execution context
        var toolRole = urGuest
        if annotOpt.isSome:
          toolRole = annotOpt.get().role
        else:
          let ent = al.contextBuilder.graph.entities[resolvedID]
          if ent.role.toLowerAscii in ["boss", "master", "admin", "superadmin"]:
            toolRole = if ent.role.toLowerAscii == "boss" or ent.role.toLowerAscii == "superadmin": urBoss else: urMaster
        opts.userRole = $toolRole
    
    if not isKnown:
      let (legacyID, found) = al.contextBuilder.relations.resolveUser(opts.channel, opts.senderID)
      if found:
        logicalUserID = legacyID
        isKnown = true

    if isKnown and opts.userRole == "Guest" and al.contextBuilder.relations.hasKey(logicalUserID):
      let ident = al.contextBuilder.relations[logicalUserID].identity
      # If the string maps to a valid UserRole, pass it; else fallback
      opts.userRole = ident

    # Check if this user is a NEW user for an agent
    if not isKnown and opts.recipientID.len > 0:
      var allInvites = loadInvites(al.workspace)
      let msgNormalized = opts.userMessage.strip().replace("-", "").toUpperAscii()
      
      for code, inv in allInvites.pairs:
        let codeNormalized = code.replace("-", "").toUpperAscii()
        # Match either pinless (Public mode) or explicit match of the PIN code
        let matchesPublic = inv.pinless and (opts.recipientID == "" or inv.agentName == opts.recipientID)
        let matchesPrivate = not inv.pinless and msgNormalized == codeNormalized and (opts.recipientID == "" or inv.agentName == opts.recipientID)
        
        if (matchesPublic or matchesPrivate) and isValid(inv):
          let sanitizedName = inv.customerName.replace(" ", "_").toLowerAscii()
          # professional ID pattern: customer_Alice_A4B
          let suffix = if opts.senderID.len >= 3: opts.senderID[0..2] else: "new"
          let newID = "customer_" & sanitizedName & "_" & suffix
          
          if al.contextBuilder.graph != nil:
            # Onboard to Graph
            var agentId = WorldEntityID(0)
            for id, ent in al.contextBuilder.graph.entities:
              if ent.kind == ekAI and ent.name == inv.agentName:
                agentId = id
                break
            
            let newEntityID = al.contextBuilder.graph.addUserToGraph(
              newID, 
              opts.senderID, 
              parseEnum[UserRole](inv.role, urGuest), 
              agentId, 
              50
            )
            logicalUserID = toAlias(newEntityID)
          else:
            # Legacy Onboarding
            var kind = ekPerson
            if opts.channel == "nkn" and opts.senderID.contains("."):
              kind = ekAI

            var rel = Relationship(
              name: newID,
              identity: $parseEnum[UserRole](inv.role, urGuest),
              trustLevel: 50,
              etiquette: "",
              kind: kind,
              identifiers: initTable[string, seq[string]]()
            )
            rel.identifiers[opts.channel] = @[opts.senderID]
            al.contextBuilder.relations[newID] = rel
            saveRelations(al.officeDir, al.contextBuilder.relations)
            logicalUserID = newID
          
          let modeText = if inv.pinless: "public mode" else: "PIN redemption"
          infoCF("agent", "Auto-onboarded via " & modeText, {"agent": opts.recipientID, "user": opts.senderID, "id": newID}.toTable)
          
          # Consume invite
          if inv.maxUses > 0:
            var mInv = inv
            mInv.maxUses -= 1
            if mInv.maxUses == 0: allInvites.del(code)
            else: allInvites[code] = mInv
            saveInvites(al.workspace, allInvites)
            
          if matchesPrivate:
            # Special case for Private Mode: Return redemption message directly and skip LLM
            return "Invite redeemed! Welcome, " & inv.customerName & ". How can I help you today?"
            
          break
      
      # Ensure Lexi keeps a record of who she's talking to
      if not isKnown:
        # Determine kind based on heuristics
        var kind = ekPerson
        if opts.channel == "nkn" and opts.senderID.contains("."):
          kind = ekAI # Has subname, likely an agent
        
        let newRel = Relationship(
          name: logicalUserID,
          identity: "Guest",
          trustLevel: 10,
          etiquette: "Professional guest service protocol.",
          kind: kind,
          identifiers: {opts.channel: @[opts.senderID]}.toTable
        )
        al.contextBuilder.relations[logicalUserID] = newRel
        saveRelations(al.officeDir, al.contextBuilder.relations)
        infoCF("agent", "Recorded new guest contact", {"id": logicalUserID, "kind": $kind, "channel": opts.channel}.toTable)
      else:
        # Update existing entry if needed (e.g. if identification changed)
        var rel = al.contextBuilder.relations[logicalUserID]
        var changed = false
        if not rel.identifiers.hasKey(opts.channel):
          rel.identifiers[opts.channel] = @[opts.senderID]
          changed = true
        elif opts.senderID notin rel.identifiers[opts.channel]:
          rel.identifiers[opts.channel].add(opts.senderID)
          changed = true
          
        if changed:
          al.contextBuilder.relations[logicalUserID] = rel
          saveRelations(al.officeDir, al.contextBuilder.relations)

    let targetRecipient = if opts.recipientID != "": opts.recipientID else: al.agentId
    var messages = al.contextBuilder.buildMessages(logicalUserID, history, summary, opts.userMessage, opts.channel, opts.chatID, useXmlTools, targetRecipient)

    let historyLabel = if logicalUserID != "": logicalUserID else: opts.senderID
    al.sessions.addMessage(opts.sessionKey, "user", historyLabel & ": " & opts.userMessage)

    # Immediate feedback: notify bus that bot is "typing"
    al.bus.publishOutbound(OutboundMessage(
      channel: opts.channel,
      sender_agent: opts.recipientID,
      chat_id: opts.chatID,
      kind: Typing,
      reply_to_message_id: opts.replyToMessageID,
      app_id: opts.appID
    ))

    let (finalContentRaw, iteration, _) = await al.runLLMIteration(ctx, messages, opts, logicalUserID)
    var finalContent = finalContentRaw

    if finalContent == "":
      finalContent = opts.defaultResponse

    if ctx.responseSent:
      infoCF("agent", "Response already sent via tools, skipping final return message", {"session_key": opts.session_key}.toTable)
      # Still add to history but return empty so gateway doesn't send it again
      al.sessions.addMessage(opts.sessionKey, "assistant", finalContent)
      al.sessions.save(al.sessions.getOrCreate(opts.sessionKey))
      return ""

    al.sessions.addMessage(opts.sessionKey, "assistant", finalContent)
    al.sessions.save(al.sessions.getOrCreate(opts.sessionKey))

    if opts.enableSummary:
      al.maybeSummarize(opts.sessionKey)

    infoCF("agent", "Response: " & truncate(finalContent, 120), {"session_key": opts.session_key, "iterations": $iteration}.toTable)
    
    # NOTE: Forged MCP tools are NOT purged here — they persist across turns within a session.
    # Use purge_mcp_tool explicitly to clean up, or tools are cleaned up on session timeout.
    
    return finalContent
  except Exception as e:
    var errMeta = newJObject()
    errMeta["error"] = %e.msg
    al.logAction(ctx, atCancel, 0, errMeta)
    al.logTaskHeader(ctx, atCancel)
    errorCF("agent", "Agent loop failed", {"error": e.msg, "agent": al.agentName}.toTable)
    return "Error: " & e.msg
  finally:
    al.logTaskHeader(ctx, atFinish)

proc processMessage*(al: AgentLoop, msg: InboundMessage): Future[string] {.async.} =
  infoCF("agent", "Processing message from " & msg.channel & ":" & msg.sender_id, {"session_key": msg.session_key}.toTable)

  # Determine streamIntermediary based on channel config, fallback to agent defaults
  let channelStreamIntermediary = case msg.channel:
    of "feishu": al.cfg.channels.feishu.stream_intermediary
    of "nmobile": al.cfg.channels.nmobile.stream_intermediary
    else: al.cfg.agents.defaults.stream_intermediary

  # Removed manual setContext calls to message/spawn/cron tools here
  # since executeWithContext now passes channel, chatID, and sessionKey correctly.

  return await al.runAgentLoop(ProcessOptions(
    sessionKey: msg.session_key,
    senderID: msg.sender_id,
    recipientID: msg.recipient_id,
    channel: msg.channel,
    chatID: msg.chat_id,
    replyToMessageID: msg.metadata.getOrDefault("message_id", ""),
    appID: msg.metadata.getOrDefault("app_id", ""),
    userMessage: msg.content,
    defaultResponse: "I've completed processing but have no response to give.",
    enableSummary: true,
    sendResponse: false,
    streamIntermediary: channelStreamIntermediary
  ))

proc processDirect*(al: AgentLoop, content, sessionKey: string, senderID: string = "user", channel: string = "cli"): Future[string] {.async.} =
  let msg = InboundMessage(channel: channel, sender_id: senderID, recipient_id: al.agentName, chat_id: "direct", content: content, session_key: sessionKey)
  return await al.processMessage(msg)

proc run*(al: AgentLoop) {.async.} =
  al.running = true
  while al.running:
    let msg = await al.bus.consumeInbound()
    try:
      let response = await al.processMessage(msg)
      if response != "":
        al.bus.publishOutbound(newOutbound(msg.channel, msg.recipient_id, msg.chat_id, response, msg.metadata.getOrDefault("message_id", ""), msg.metadata.getOrDefault("app_id", "")))
    except Exception as e:
      errorCF("agent", "Failed to process message", {"error": e.msg, "session": msg.session_key}.toTable)
      al.bus.publishOutbound(newOutbound(msg.channel, msg.recipient_id, msg.chat_id,
        "I encountered an error while processing your request: " & e.msg,
        msg.metadata.getOrDefault("message_id", ""), msg.metadata.getOrDefault("app_id", "")
      ))

proc newAgentLoop*(cfg: Config, msgBus: MessageBus, provider: LLMProvider, agentName: string = "Lexi", cronService: CronService = nil, model: string = ""): AgentLoop =
  debugCF("agentLoop", "Initializing", {"agent": agentName}.toTable)
  let workspace = cfg.workspacePath()
  let officeDir = workspace / "offices" / agentName.toLowerAscii()
  
  # Load agent-specific environment from office dir
  let agentEnv = officeDir / ".env"
  if fileExists(agentEnv):
    infoCF("agent", "Loading office-specific .env", {"path": agentEnv, "agent": agentName}.toTable)
    for line in readFile(agentEnv).splitLines():
      let pair = line.split("=", 1)
      if pair.len == 2:
        let key = pair[0].strip()
        let val = pair[1].strip()
        if key.len > 0: putEnv(key, val)
  
  createDir(workspace)
  for subdir in ["mail", "notes", "memory", "sessions", "skills", "mcp"]:
    createDir(officeDir / subdir)

  let nimclawDir = getNimClawDir()
  for subdir in ["skills", "plugins"]:
    createDir(nimclawDir / subdir)

  var role = "Agent" # Default fallback
  var entity = "AI"
  var identity = "Agent"
  for a in cfg.agents.named:
    if a.name == agentName:
      if a.role.isSome:
        role = a.role.get()
      if a.entity != "":
        entity = a.entity
      if a.identity != "":
        identity = a.identity
      break

  let toolsRegistry = newToolRegistry()

  # Shared HTTP client for tools (closed in stop())
  let toolCurly = newCurly()

  # Register all tools faithfully as in Go
  var allowedPaths = cfg.agents.security.allowed_paths
  
  # Initialize SkillsLoader to discover all skill paths for security allowlist
  let loader = skills_loader.newSkillsLoader(
    workspace,
    workspace / ".nimclaw" / "workspace" / "competencies",
    officeDir / "skills",
    getHomeDir() / ".nimclaw",
    getHomeDir() / ".nimclaw" / "os",
    getEnv("OPENCLAW_EXTENSIONS", getHomeDir() / ".openclaw" / "extensions")
  )
  
  # Add all discovered skill locations to allowed paths
  for s in loader.listSkills():
    if s.location notin allowedPaths:
      allowedPaths.add(s.location)

  toolsRegistry.register(newReadFileTool(workspace, officeDir, allowedPaths))
  toolsRegistry.register(newWriteFileTool(workspace, officeDir, allowedPaths))
  toolsRegistry.register(newListDirTool(workspace, officeDir, allowedPaths))
  toolsRegistry.register(newExecTool(workspace))
  toolsRegistry.register(newClockTool())

  toolsRegistry.register(newWebSearchTool(cfg.tools.web.search.api_key, cfg.tools.web.search.max_results, toolCurly, createMaster()))
  toolsRegistry.register(newWebFetchTool(50000, toolCurly, createMaster()))
  toolsRegistry.register(newHttpRequestTool())
  toolsRegistry.register(newGitTool(workspace, cfg.agents.security.allowed_paths, officeDir))
  toolsRegistry.register(newPushoverTool(workspace))
  toolsRegistry.register(newScreenshotTool(workspace))
  toolsRegistry.register(newImageInfoTool())
  
  let composioKey = getEnv("COMPOSIO_API_KEY", "")
  toolsRegistry.register(newComposioTool(composioKey))

  let allowedDomainsStr = getEnv("BROWSER_ALLOWED_DOMAINS", "")
  var allowedBrowserDomains: seq[string] = @[]
  if allowedDomainsStr.len > 0:
    for d in allowedDomainsStr.split(','):
      let t = d.strip()
      if t.len > 0: allowedBrowserDomains.add(t)
      
  toolsRegistry.register(newBrowserOpenTool(allowedBrowserDomains))

  let callback: SendCallback = proc(channel, chatID, content, senderAgent, replyToMessageID, appID: string): Future[void] {.async.} =
    msgBus.publishOutbound(newOutbound(channel, senderAgent, chatID, content, replyToMessageID, appID))



  let subagentManager = newSubagentManager(provider, workspace, msgBus, toolsRegistry, nil)
  toolsRegistry.register(newSpawnTool(subagentManager))

  toolsRegistry.register(newHardwareBoardInfoTool(cfg.peripherals.boards))
  toolsRegistry.register(newHardwareMemoryTool(cfg.peripherals.boards))
  toolsRegistry.register(newI2cTool())
  toolsRegistry.register(newSpiTool())
  toolsRegistry.register(newDelegateTool(workspace, cfg.agents.named))
  toolsRegistry.register(newRedeemInviteTool())

  # Orchestration Tools
  toolsRegistry.register(newSendMailTool(workspace))
  toolsRegistry.register(newTaskOrchestratorTool(workspace))
  toolsRegistry.register(newClaimTaskTool(workspace))
  toolsRegistry.register(newSubmitTaskTool(workspace))
  toolsRegistry.register(newUpdateContactTool(officeDir))

  toolsRegistry.register(newEditFileTool(workspace))
  toolsRegistry.register(newAppendFileTool(workspace))
  toolsRegistry.register(newPersistTool(toolsRegistry))
  toolsRegistry.register(newPersistSkillTool(toolsRegistry))
  toolsRegistry.register(newForgeTool(toolsRegistry, officeDir))
  toolsRegistry.register(newPurgeMcpTool(toolsRegistry, officeDir))
  toolsRegistry.register(newSetApiKeyTool(getConfigPath()))
  toolsRegistry.register(newJqTool(workspace))
  
  let installer = newSkillInstaller(officeDir)
  toolsRegistry.register(newSkillInstallTool(installer))
  
  let sessionsManager = newSessionManager(officeDir / "sessions")
  let contextBuilder = newContextBuilder(officeDir, workspace, cfg.agents.named)
  contextBuilder.tools = toolsRegistry # Manually bridge for now

  let msgTool = newMessageTool()
  msgTool.setSendCallback(callback)
  
  let injectCb: InjectSessionCallback = proc(sessionKey, role, content: string): Future[void] {.async.} =
    sessionsManager.addMessage(sessionKey, role, content)
    sessionsManager.save(sessionsManager.getOrCreate(sessionKey))
  msgTool.setInjectCallback(injectCb)
  toolsRegistry.register(msgTool)

  let rTool = newReplyTool()
  rTool.setSendCallback(callback)
  toolsRegistry.register(rTool)

  let fwdTool = newForwardTool(officeDir)
  fwdTool.setSendCallback(callback)
  toolsRegistry.register(fwdTool)

  toolsRegistry.register(newListTools(toolsRegistry))
  toolsRegistry.register(newQueryGraphTool(contextBuilder))

  # Phase 400: Scan persistent libraries and OS tools
  let nimclawBase = getHomeDir() / ".nimclaw"
  let searchDirs = [
    nimclawBase / "os",
    nimclawBase / "mcp" / "tools"
  ]
  
  for baseDir in searchDirs:
    if dirExists(baseDir):
      for kind, path in walkDir(baseDir):
        if kind == pcDir:
          let toolName = path.lastPathPart()
          let binName = if hostOS == "windows": toolName & ".exe" else: toolName
          let binaryPath = path / binName
          if fileExists(binaryPath):
            infoCF("agent", "Loading persistent MCP tool", {"name": toolName, "path": binaryPath}.toTable)
            # Use 'system' as session key for persistent tools so they aren't purged
            discard toolsRegistry.registerMcpServer(binaryPath, @[], "system", @[])
  
  # Phase 401: Scan agent-specific forged MCP tools
  let officeMcpDir = officeDir / "mcp"
  if dirExists(officeMcpDir):
    for kind, path in walkDir(officeMcpDir):
        if kind == pcDir:
          let toolName = path.lastPathPart()
          let binName = if hostOS == "windows": toolName & ".exe" else: toolName
          
          # Check new structure (bin/tool)
          var binaryPath = path / "bin" / binName
          if not fileExists(binaryPath):
            # Fallback to old structure (root/tool)
            binaryPath = path / binName
            
          if fileExists(binaryPath):
            infoCF("agent", "Loading forged office-specific MCP tool", {"name": toolName, "path": binaryPath, "agent": agentName}.toTable)
            # Use agent's name as session key for personal forged tools so they persist
            discard toolsRegistry.registerMcpServer(binaryPath, @[], agentName, @[])
  
  let markdownMemory = newMarkdownMemory(officeDir, workspace)
  toolsRegistry.register(newMemoryStoreTool(markdownMemory))
  toolsRegistry.register(newMemoryListTool(markdownMemory))
  toolsRegistry.register(newMemoryRecallTool(markdownMemory))
  toolsRegistry.register(newMemoryForgetTool(markdownMemory))

  var al = AgentLoop(
    bus: msgBus,
    provider: provider,
    workspace: workspace,
    officeDir: officeDir,
    cfg: cfg,
    agentName: agentName,
    role: role,
    entity: entity,
    identity: identity,
    model: if model != "": model else: cfg.agents.defaults.model,
    contextWindow: cfg.agents.defaults.max_tokens,
    temperature: cfg.agents.defaults.temperature,
    maxIterations: cfg.agents.defaults.max_tool_iterations,
    sessions: sessionsManager,
    contextBuilder: contextBuilder,
    tools: toolsRegistry,
    cronService: cronService,
    summarizing: initTable[string, bool](),
    agentId: "",
    curly: toolCurly
  )
  debugCF("agentLoop", "Instance created", {"agent": agentName}.toTable)
  initLock(al.summarizingLock)

  # Resolve agentId from WorldGraph (nc:ID format)
  if contextBuilder.graph != nil and contextBuilder.graph.nameIndex.hasKey(agentName):
    al.agentId = toAlias(contextBuilder.graph.nameIndex[agentName])
  else:
    al.agentId = agentName  # Fallback to name if no graph

  # Register CronTool using the loop instance for execution
  if cronService != nil:
    let cronExecutor = proc(content, sessionKey, channel, chatID: string): Future[string] {.async.} =
      let msg = InboundMessage(
        channel: channel,
        sender_id: "system:scheduler",
        recipient_id: "",
        chat_id: chatID,
        content: content,
        session_key: sessionKey
      )
      return await al.processMessage(msg)
    
    toolsRegistry.register(newCronTool(cronService, cronExecutor, msgBus))

  return al

proc getStartupInfo*(al: AgentLoop): Table[string, JsonNode] =
  var info = initTable[string, JsonNode]()
  info["tools"] = %*{"count": al.tools.list().len, "names": al.tools.list()}
  info["skills"] = %al.contextBuilder.getSkillsInfo()
  return info
