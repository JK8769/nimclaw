import std/[asyncdispatch, tables, json, locks, times, strutils, sets]
import types, ../mcp
import ../logger
import ../providers/types as providers_types
import ../schema

const
  ExternalUserRoles = ["guest", "customer"]
  ExternalAllowedTools* = ["reply", "forward", "redeem_invite", "update_contact"]

type
  ToolRegistry* = ref object
    tools: Table[string, Tool]
    mcpClients: Table[string, McpClient] # serverName -> client
    sessionMcpServers: Table[string, HashSet[string]] # sessionKey -> set of serverNames
    lock: Lock

proc sanitizeToolName*(name: string): string =
  ## Ensures a tool name is safe for LLM providers (DeepSeek, etc).
  ## Allows: a-z, A-Z, 0-9, _, -
  result = ""
  for c in name:
    if c in {'a'..'z', 'A'..'Z', '0'..'9', '_', '-'}:
      result.add(c)
    else:
      result.add('_')

proc newToolRegistry*(): ToolRegistry =
  ## Creates a new, thread-safe ToolRegistry.
  ##
  runnableExamples:
    let tr = newToolRegistry()
    doAssert tr.count == 0
  ##
  var tr = ToolRegistry(
    tools: initTable[string, Tool](),
    mcpClients: initTable[string, McpClient](),
    sessionMcpServers: initTable[string, HashSet[string]]()
  )
  initLock(tr.lock)
  return tr

proc register*(r: ToolRegistry, tool: Tool) =
  ## Registers a new tool in the registry.
  acquire(r.lock)
  defer: release(r.lock)
  let sname = sanitizeToolName(tool.name())
  r.tools[sname] = tool

proc registerMcpServer*(tr: ToolRegistry, command: string, args: seq[string] = @[], sessionKey: string = "", sandbox: seq[string] = @[]): Future[void] {.async.} =
  let client = await connectMcpServer(command, args, sandbox)
  
  acquire(tr.lock)
  tr.mcpClients[client.serverName] = client
  if sessionKey != "":
    if not tr.sessionMcpServers.hasKey(sessionKey):
      tr.sessionMcpServers[sessionKey] = initHashSet[string]()
    tr.sessionMcpServers[sessionKey].incl(client.serverName)
  release(tr.lock)
  
  let mcpTools = await client.listTools()
  for t in mcpTools:
    tr.register(t)
  infoCF("tool", "Registered MCP server tools", {"server": client.serverName, "count": $mcpTools.len}.toTable)

proc unregister*(r: ToolRegistry, name: string) =
  acquire(r.lock)
  defer: release(r.lock)
  r.tools.del(sanitizeToolName(name))

proc unregisterMcpServer*(r: ToolRegistry, serverName: string) =
  acquire(r.lock)
  let ok = r.mcpClients.hasKey(serverName)
  var client: McpClient = nil
  if ok:
    client = r.mcpClients[serverName]
    r.mcpClients.del(serverName)
  release(r.lock)

  if client != nil:
    client.stop()
    
    # Remove all tools prefixed with mcp_[serverName]_
    let prefix = "mcp_" & serverName & "_"
    var toRemove: seq[string] = @[]
    
    acquire(r.lock)
    for k in r.tools.keys:
      if k.startsWith(prefix):
        toRemove.add(k)
    for k in toRemove:
      r.tools.del(k)
    release(r.lock)
    infoCF("tool", "Unregistered MCP server tools", {"server": serverName, "count": $toRemove.len}.toTable)

proc stopAllMcpClients*(r: ToolRegistry) =
  ## Stops all registered MCP clients and clears the registry.
  var clients: seq[McpClient] = @[]
  acquire(r.lock)
  for c in r.mcpClients.values:
    clients.add(c)
  r.mcpClients.clear()
  r.tools.clear() # Optional: also clear tools associated with MCPs
  release(r.lock)
  
  for client in clients:
    try: client.stop()
    except: discard

proc purgeSession*(r: ToolRegistry, sessionKey: string) =
  var servers: seq[string] = @[]
  acquire(r.lock)
  if r.sessionMcpServers.hasKey(sessionKey):
    for s in r.sessionMcpServers[sessionKey]:
      servers.add(s)
    r.sessionMcpServers.del(sessionKey)
  release(r.lock)
  
  for s in servers:
    r.unregisterMcpServer(s)

proc get*(r: ToolRegistry, name: string): (Tool, bool) =
  acquire(r.lock)
  defer: release(r.lock)
  let sname = sanitizeToolName(name)
  if r.tools.hasKey(sname):
    return (r.tools[sname], true)
  else:
    return (nil, false)

proc list*(r: ToolRegistry): seq[string] =
  ## Returns a list of all registered tool names.
  acquire(r.lock)
  defer: release(r.lock)
  for k in r.tools.keys:
    result.add(k)

proc count*(r: ToolRegistry): int =
  ## Returns the total number of registered tools.
  acquire(r.lock)
  defer: release(r.lock)
  r.tools.len

proc getSummaries*(r: ToolRegistry): seq[string] =
  acquire(r.lock)
  defer: release(r.lock)
  for tool in r.tools.values:
    result.add("- `" & sanitizeToolName(tool.name()) & "` - " & tool.description())

proc getSummariesFiltered*(r: ToolRegistry, allowed: seq[string]): seq[string] =
  var allowedSet = initHashSet[string]()
  for a in allowed:
    allowedSet.incl(sanitizeToolName(a))
  acquire(r.lock)
  defer: release(r.lock)
  for tool in r.tools.values:
    let n = sanitizeToolName(tool.name())
    if allowedSet.contains(n):
      result.add("- `" & n & "` - " & tool.description())

proc toolToSchema*(tool: Tool, strategy: CleaningStrategy): ToolDefinition =
  let rawParams = %*(tool.parameters())
  let cleanedParams = cleanForStrategy(rawParams, strategy)
  ToolDefinition(
    `type`: "function",
    function: ToolFunctionDefinition(
      name: sanitizeToolName(tool.name()),
      description: tool.description(),
      parameters: cleanedParams
    )
  )

proc getDefinitions*(r: ToolRegistry, strategy: CleaningStrategy): seq[ToolDefinition] =
  acquire(r.lock)
  defer: release(r.lock)
  for tool in r.tools.values:
    result.add(toolToSchema(tool, strategy))

proc getDefinitionsFiltered*(r: ToolRegistry, strategy: CleaningStrategy, allowed: seq[string]): seq[ToolDefinition] =
  var allowedSet = initHashSet[string]()
  for a in allowed:
    allowedSet.incl(sanitizeToolName(a))
  acquire(r.lock)
  defer: release(r.lock)
  for tool in r.tools.values:
    let n = sanitizeToolName(tool.name())
    if allowedSet.contains(n):
      result.add(toolToSchema(tool, strategy))

proc executeWithContext*(r: ToolRegistry, name: string, args: Table[string, JsonNode], ctx: ToolContext): Future[string] {.async.} =
  infoCF("tool", "Tool execution started", {"tool": name, "args": $args, "role": ctx.role, "entity": ctx.entity, "identity": ctx.identity}.toTable)

  let (tool, ok) = r.get(name)
  if not ok:
    errorCF("tool", "Tool not found", {"tool": name}.toTable)
    return "Error: tool '" & name & "' not found"

  let roleLow = ctx.role.toLowerAscii()
  if roleLow in ExternalUserRoles:
    let tname = sanitizeToolName(name)
    if tname notin ExternalAllowedTools:
      return "Error: Tool '" & tname & "' is not available for external users."

  if tool of ContextualTool and ctx.channel != "" and ctx.chatID != "":
    (cast[ContextualTool](tool)).setContext(ctx)


  let start = now()
  var result = ""
  try:
    result = await tool.execute(args)
  except Exception as e:
    let duration = (now() - start).inMilliseconds
    errorCF("tool", "Tool execution failed", {"tool": name, "duration": $duration, "error": e.msg}.toTable)
    return "Error: " & e.msg

  let duration = (now() - start).inMilliseconds
  infoCF("tool", "Tool execution completed", {"tool": name, "duration_ms": $duration, "result_length": $result.len}.toTable)
  return result
