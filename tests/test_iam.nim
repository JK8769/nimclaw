import std/[os, json, asyncdispatch, tables, strutils]
import src/nimclaw/tools/[types, filesystem, registry, iam_policies]

proc runTest() {.async.} =
  let workspace = absolutePath("test_workspace")
  if dirExists(workspace): removeDir(workspace)
  createDir(workspace)
  createDir(workspace / "offices")
  createDir(workspace / "offices" / "lexi")
  createDir(workspace / "offices" / "robin")
  createDir(workspace / "collaboration")
  createDir(workspace / "collaboration" / "staging")
  createDir(workspace / "competencies")
  createDir(workspace / "memos")
  createDir(workspace / "portal")
  
  writeFile(workspace / "offices" / "robin" / "secret.txt", "Robin's secret")
  writeFile(workspace / "offices" / "lexi" / "notes.txt", "Lexi's notes")
  
  let reg = newToolRegistry()
  let readTool = newReadFileTool(workspace, workspace / "offices" / "lexi", @[])
  let writeTool = newWriteFileTool(workspace, workspace / "offices" / "lexi", @[])
  reg.register(readTool)
  reg.register(writeTool)

  # TEST 1: Lexi (Employee) attempts to write to Robin's office
  echo "--- TEST 1: Employee (Lexi) writing to Robin's office ---"
  let res1 = await reg.executeWithContext("write_file", 
    {"path": %"offices/robin/hack.txt", "content": %"hacked"}.toTable,
    "test", "chat1", "sess1", "user1", "Lexi", 
    role = "Employee"
  )
  echo "Result: ", res1
  if res1.contains("IAM Permission Denied"):
    echo "SUCCESS: Blocked correctly."
  else:
    echo "FAILURE: Lexi was allowed to write to Robin's office!"

  # TEST 2: Lexi (Employee) attempts to write to her own office
  echo "\n--- TEST 2: Employee (Lexi) writing to own office ---"
  let res2 = await reg.executeWithContext("write_file", 
    {"path": %"offices/lexi/task.md", "content": %"Done"}.toTable,
    "test", "chat1", "sess1", "user1", "Lexi", 
    role = "Employee"
  )
  echo "Result: ", res2
  if res2.contains("successfully"):
    echo "SUCCESS: Allowed correctly."
  else:
    echo "FAILURE: Lexi was blocked from her own office!"

  # TEST 3: Raven (SuperAdmin) attempts to write to Robin's office
  echo "\n--- TEST 3: SuperAdmin (Raven) writing to Robin's office ---"
  let res3 = await reg.executeWithContext("write_file", 
    {"path": %"offices/robin/audit.txt", "content": %"Audited"}.toTable,
    "test", "chat1", "sess1", "user1", "Raven", 
    role = "SuperAdmin"
  )
  echo "Result: ", res3
  if res3.contains("successfully"):
    echo "SUCCESS: SuperAdmin bypass confirmed."
  else:
    echo "FAILURE: SuperAdmin was blocked!"

  # TEST 4: Lexi (Employee) reading Robin's office
  # Per policy: Employee can read staging/handbook/own office, but not another office
  echo "\n--- TEST 4: Employee (Lexi) reading Robin's office ---"
  let res4 = await reg.executeWithContext("read_file", 
    {"path": %"offices/robin/secret.txt"}.toTable,
    "test", "chat1", "sess1", "user1", "Lexi", 
    role = "Employee"
  )
  echo "Result: ", res4
  if res4.contains("IAM Permission Denied"):
    echo "SUCCESS: Read blocked correctly."
  else:
    echo "FAILURE: Lexi read Robin's secret!"

  # TEST 5: Employee (Lexi) writing to Portal
  echo "\n--- TEST 5: Employee (Lexi) writing to Portal ---"
  let res5 = await reg.executeWithContext("write_file", 
    {"path": %"portal/news.md", "content": %"Lexi was here"}.toTable,
    "test", "chat1", "sess1", "user1", "Lexi", 
    role = "Employee"
  )
  echo "Result: ", res5
  if res5.contains("IAM Permission Denied"):
    echo "SUCCESS: Portal write blocked for employee."
  else:
    echo "FAILURE: Lexi wrote to portal!"

  # TEST 6: Employee (Lexi) writing to Memos (Company Memory)
  echo "\n--- TEST 6: Employee (Lexi) writing to Memos (Company Memory) ---"
  let res6 = await reg.executeWithContext("write_file", 
    {"path": %"memos/note.md", "content": %"Shared memo"}.toTable,
    "test", "chat1", "sess1", "user1", "Lexi", 
    role = "Employee"
  )
  echo "Result: ", res6
  if res6.contains("IAM Permission Denied"):
    echo "SUCCESS: Memos are read-only for employees."
  else:
    echo "FAILURE: Lexi was allowed to write to the company memory (memos)!"

  # TEST 7: Employee (Lexi) writing to Collaboration
  echo "\n--- TEST 7: Employee (Lexi) writing to Collaboration ---"
  let res7 = await reg.executeWithContext("write_file", 
    {"path": %"collaboration/ideas.md", "content": %"Creative ideas"}.toTable,
    "test", "chat1", "sess1", "user1", "Lexi", 
    role = "Employee"
  )
  echo "Result: ", res7
  if res7.contains("successfully"):
    echo "SUCCESS: Collaboration folder is open."
  else:
    echo "FAILURE: Lexi couldn't write to collaboration!"

  # TEST 8: Employee (Lexi) attempting to access .nimclaw internal files
  echo "\n--- TEST 8: Employee (Lexi) accessing internal .nimclaw config ---"
  let dotNimclaw = expandTilde("~/.nimclaw/BASE.json")
  let res8 = await reg.executeWithContext("read_file", 
    {"path": %dotNimclaw}.toTable,
    "test", "chat1", "sess1", "user1", "Lexi", 
    role = "Employee"
  )
  echo "Result: ", res8
  if res8.contains("IAM Permission Denied") or res8.contains("not allowed"):
    echo "SUCCESS: Internal config restricted."
  else:
    echo "FAILURE: Lexi read .nimclaw internal config!"

  # Cleanup

  removeDir(workspace)

waitFor runTest()
