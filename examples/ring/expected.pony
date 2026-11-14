use "collections"

class val Job
  var _id: U32
  var _payload: U32

  new create(id': U32, payload': U32) =>
    _id = id'
    _payload = payload'

  fun id(): U32 =>
    _id

  fun payload(): U32 =>
    _payload

actor Collector
  var _stream: OutStream
  var _pending: USize
  var _total: U64 = 0

  new create(stream: OutStream, expected: USize) =>
    _stream = stream
    _pending = expected

  be collect(id: U32, value: U64) =>
    _total = _total + value
    _pending = _pending - 1
    if _pending == 0 then
      _stream.print("collected total = " + _total.string())
    end

actor Worker
  var _id: U32
  var _sink: Collector tag

  new create(id: U32, sink: Collector tag) =>
    _id = id
    _sink = sink

  be run(job: Job) =>
    var value = job.payload().u64() * _id.u64()
    _sink.collect(job.id(), value)

actor Main
  new create(env: Env) =>
    var count: USize = 4
    var sink = Collector.create(env.out, count)
    var workers = Array[Worker].create()
    for i in Range[USize].till(0, count) do
      workers.push(Worker.create((i + 1).u32(), sink))
    end
    for (i, w) in workers.pairs() do
      w.run(Job.create(where id' = i.u32(), payload' = 10))
    end
