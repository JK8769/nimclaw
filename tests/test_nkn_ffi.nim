import std/[os, strutils, json, unittest, asyncdispatch]
import ../src/nimclaw/libnkn/nknWallet

suite "NKN FFI Stability Tests":
  var walletJson: string
  var password = "test-password-1234"
  var clientAddr: string

  test "Generate Wallet":
    let (res, err) = getWallet(password)
    check err == ""
    check res != ""
    walletJson = res
    echo "Wallet generated successfully"

  test "Create NKN Client":
    # Creating a client requires connectivity usually, but let's see if it crashes
    echo "Setting up NKN client (this may take a moment)..."
    let (nknAddress, err) = createNKNClient(walletJson, password, "test-bot")
    if err != "":
      echo "Skipping client tests due to connection error: ", err
    else:
      check nknAddress != ""
      clientAddr = nknAddress
      echo "Client connected: ", nknAddress

  test "Stress Test Polling (PopNKNMessage)":
    if clientAddr == "":
      skip()
    
    echo "Starting stress test of PopNKNMessage..."
    for i in 1..1000:
      let (src, data, err) = popNKNMessage(clientAddr)
      if err != "":
        echo "Poll error at iteration ", i, ": ", err
        break
      # We don't care if a message is returned, just that it doesn't crash
      if i mod 100 == 0:
        echo "Completed ", i, " poll iterations"
    
    echo "Stress test completed without SIGSEGV"

  test "Nil/Invalid Input Resilience":
    # We should test if our Nim wrapper handles potential nil returns from Go (though we fixed Go to not return nil)
    # But more importantly, how does it handle garbage?
    # Actually, we want to see if calling with empty strings or invalid IDs causes crash
    let (src, data, err) = popNKNMessage("")
    check err != ""
    echo "Handled empty clientAddr: ", err

  test "Multiple Clients (Thread Safety check)":
    if walletJson == "": skip()
    echo "Testing multiple clients setup..."
    var clients: seq[string] = @[]
    for i in 1..3:
      let (nAddress, err) = createNKNClient(walletJson, password, "bot-" & $i)
      if err == "":
        clients.add(nAddress)
    
    echo "Created ", clients.len, " clients"
    for nAddress in clients:
      discard closeNKNClient(nAddress)

  test "Async Polling (Parallel to nmobile.nim)":
    if clientAddr == "": skip()
    echo "Starting async polling simulation..."
    
    var running = true
    var iterations = 0
    
    proc asyncPoller() {.async.} =
      while running:
        try:
          let (src, data, err) = popNKNMessage(clientAddr)
          if err != "":
            echo "Async poll error: ", err
          iterations += 1
          await sleepAsync(10) # Fast polling
        except Exception as e:
          echo "Async poller exception: ", e.msg
          break

    # Start the poller
    let pollerFuture = asyncPoller()
    
    # Run for a few seconds
    for _ in 1..20:
      poll(100)
      if pollerFuture.finished: break
    
    running = false
    waitFor pollerFuture
    echo "Async polling completed with ", iterations, " iterations"
