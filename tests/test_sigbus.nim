import std/[asyncdispatch, tables, os]

type
  Job = object
    id: string

  Handler = proc(job: Job): Future[void] {.async.}

  Service = ref object
    onJob: Handler

proc run(s: Service) {.async.} =
  let job = Job(id: "test")
  if s.onJob != nil:
    echo "Triggering..."
    await s.onJob(job)
    echo "Finished."

var gS: Service = nil

proc globalHandler(job: Job): Future[void] {.async.} =
  echo "In handler: ", job.id
  await sleepAsync(100)
  echo "Leaving handler."

proc main() =
  let s = Service()
  s.onJob = globalHandler
  gS = s
  
  asyncCheck s.run()
  runForever()

main()
