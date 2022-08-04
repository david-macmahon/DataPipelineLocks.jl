# DataPipelineLocks

`DataPipelineLocks` facilitate synchronization between asynchronous threads
and/or tasks comprising a *data processing pipeline*, often referred to as
simply a *data pipeline*.

# Data pipelines

Although `DataPipelineLocks` are agnostic about the details of the data 
pipeline, a basic understanding of the data pipeline model is useful for
understanding the motivation for and usage of `DataPipelineLocks`.

A data pipeline consists of multiple threads and/or tasks (hereafter referred to
as just "tasks") that typically process data from their input data buffer to
their output data buffer.  The tasks are setup in a daisy chain manner where
each task's output data buffer is another task's input data buffer, except for
the first and last tasks which have only an output and an input buffer,
respectively.  Essentially, the first task is a *producer* or data and the last
task is the *consumer* of data.  All other intervening tasks are *propagators*,
i.e. both consumer and producer.  The functions `produce`, `propagate`, and
`consume` encapsulate the relevant machinations and utilize caller-supplied
functions to perform the desired data transfer/processing.

A data pipeline will generally use one `DataPipelineLock` between each
consecutive pair of tasks, but more complex arrangements are possible.

# Data Pipeline Termination

To facilitate the termination of the asynchronous tasks of a data pipeline,
`DataPipelineLock` instances can be *terminated* using the `terminate!`
function.  When a `DataPipelineLock` instance in terminated, any task waiting on
that instance will throw a `DataPipelineTerminated` exception and any future
operation of the terminated `DataPipelineLock` instance will also throw the same
type of exception.  Tasks may catch this exception to perform any cleanup that
may be required before terminating.  Simple tasks without cleanup requirements
may simply opt to let the exception end the task.  To terminate an entire
pipeline, all `DataPipelineLock` instances of the data pipeline should be
terminated and `wait` should be called on all tasks to ensure that they finish.
Calling `wait` on tasks that do not catch the `DataPipelineTerminated` will
itself throw a `TaskFailedException` which must be caught so as not to
prematurely exit the main task.  If desired, the termination status of a
`DataPipelineLock` instance may be obtained by passing it to the `isterminated`
function.

The `produce`, `propagate`, and `consume` functions normally return `true`, but
upon catching a `DataPipelineTerminated` exception, they will return `false`.
Tasks that use these functions should perform any cleanup required and exit when
`false` is returned.

Furthermore, `propagate` will also call `terminate!` on the downstream
`DataPipelineLock` object to propagate the termination status down the pipeline.
Any propagation tasks that does not use `propagate` should likewise propagate
any termination status to its downstream `DataPipelineLock` object.  This
convention allows for the data pipeline to be terminated by calling `terminate!`
on the first `DataPipelineLock` instance of the data pipeline and then calling
`wait` on the last task of the data pipeline.

# Examples

## Simple "one shot" example

Here is a simplified data pipeline that demonstrates the usage of
`DataPipelineLocks`.  This example is a modified version of one of the
`DataPipelineLocks` tests.  The "data buffer" in this example is simply a `Ref`
container that holds an integer.  The "producer" task is the main Task while the
consumer task is started via `@async`.

```julia
using DataPipelineLocks

databuf = Ref(0)
dpl = DataPipelineLock()

consumer = @async consume($dpl, $databuf) do d
    result = 10 * d[] + 3
    println("pipeline result is $result")
end

producer = @async produce($dpl, $databuf) do d
    d[] = rand(1:9)
end

wait(consumer)
```

## More realistic example

Normally the tasks in a data pipeline will loop many times to process multiple
blocks of data rather than perform a one-shot operation like the above example.
The example below presents a somewhat more realistic data pipeline with three
tasks: a "producer" task, a "propagator" task, and a "consumer" task.  The data
buffers `bufin` and `bufout` are `Vector{Int}` and each gets a corresponding
`DataPipelineLock` instance, `dplin` and `dplout` respectively.  The "producer"
task calls `produce` three times, each time populating `bufin` with random
integers in the range `1:9`.  The "propagator" task modifies and propagates the
data from `bufin` to `bufout`.  The "consumer" task consumes the data from
`bufout` by printing it.

The lifecycle of this pipeline, managed by the main task, is driven by the fact
that the producer task calls `produce` three times in a `for` loop and then
ends.  After starting the pipeline, the main task performs these steps to make
sure the pipeline completes cleanly (i.e. with all data processed and all tasks
completed):

1. The main task waits for the producer thread to finish.

2. The  main task waits for all locks to be free.  After the producer task has
   finished the other tasks are still running and potentially still processing
   data.  To ensure that all the data get processed through the pipeline, the
   main task waits for all the `DataPipelineLock` instances to be free.

3. The main task uses `terminate!` to terminate the `DataPipelineLock` of the
   first data buffer, `dplin`.  After all the data have passed through the data
   pipeline, the other (i.e.  non-producer) task are still running, waiting for
   more input that will never come.  Terminating the lock of the first data
   buffer starts a cascade effect that results in all tasks ending.

   - The `propagate` function used by the propagator task has been waiting for
     `dplin` to be marked "filled" indicating more data, but when `dplin` is
     terminated the `propagate` function catches a `DataPipelineTerminated`
     exception, terminates its output `DataPipelineLock` instance (i.e.
     `dplout`) and then returns `false` which causes the propagator task to end.

   - Once `dplout` is terminated a similar process happens for for consumer
     thread.

   Propagating pipeline tasks that opt not to use `propagate` should ensure that
   they handle `DataPipelineTerminated` exceptions in a similar manner to
   maintain the cascading pattern of `DataPipelineLock` terminations.

4. The main task waits for the final task of the data pipeline, in this case the
   consumer task, to complete.  After terminating the `DataPipelineLock` of the
   first data buffer, the main task tracks the cascade of lock terminations and
   task completions by waiting for the remaining tasks to complete.

```julia
using DataPipelineLocks
import Random: rand!

bufin  = Vector{Int}(undef, 4)
bufout = Vector{Int}(undef, 4)

dplin  = DataPipelineLock()
dplout  = DataPipelineLock()

producer = @async begin
    for i=1:3
        produce($dplin, $bufin) do d
            rand!(d, 1:9)
        end
    end
end

propagator = @async while propagate($dplin, $dplout, $bufin, $bufout) do din, dout
    dout .= 10 .* din .+ 3
end
end

consumer = @async while consume($dplout, $bufout) do d
    println("pipeline result is $d")
end
end

# 1. Wait for producer to finish
wait(producer)

# 2. Wait for locks to be free
waitfree(dplin)
waitfree(dplout)

# 3. Terminate first lock
terminate!(dplin)

# 4. Wait for remaining tasks to finish
wait(propagator)
wait(consumer)
```
