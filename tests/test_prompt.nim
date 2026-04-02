import std/[options, json, tables, strutils]
import src/nimclaw/agent/cortex
import src/nimclaw/agent/context
import src/nimclaw/providers/types

proc main() =
  let workspace = "/Users/owaf/Work/Agents/nimclaw/.nimclaw/workspace/offices/lexi"
  let cb = newContextBuilder(workspace, "/Users/owaf/Work/Agents/nimclaw/.nimclaw")
  
  if cb.graph == nil:
    quit("Failed to load graph")
    
  try:
    echo "--- Testing Social Section for nc:3 talking to nc:2 ---"
    let social = cb.buildSocialSection("nc:3", "nc:2", "feishu")
    echo "SUCCESS!"
    echo social
  except Exception as e:
    echo "Exception caught: ", e.msg
    echo e.getStackTrace()
main()
