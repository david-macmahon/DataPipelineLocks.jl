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
i.e. both consumer and producer.

A data pipeline will generally use one `DataPipelineLock` between each
consecutive pair of tasks, but more complex arrangements are possible.

# Data Pipeline Termination

To facilitate the termination of the asynchronous tasks of a data pipeline,
`DataPipelineLock` instances can be *terminated* using the `terminate!`
function.  When a `DataPipelineLock` instance in terminated, any task waiting on
that instance will throw a `DataPipelineTerminatedException` exception and any
future operation of the terminated `DataPipelineLock` instance will also throw
the same type of exception.  Tasks may catch this exception to perform any
cleanup that may be required before terminating.  Simple tasks without cleanup
requirements may simply opt to let the exception end the task.  To terminate an
entire pipeline, all `DataPipelineLock` instances of the data pipeline should be
terminated and `wait` should be called on all tasks to ensure that they finish.
Calling `wait` on tasks that do not catch the `DataPipelineTerminatedException`
will itself throw a `TaskFailedException` which must be caught so as not to
prematurely exit the main task.  If desired, the termination status of a
`DataPipelineLock` instance may be obtained by passing it to the `isterminated`
function.

# Examples

Here is a simplified data pipeline that demonstrates the usage of
`DataPipelineLocks`.  This example is a modified version of one of the
`DataPipelineLocks` tests.  The "data buffer" in this example is simply a `Ref`
container that holds an integer.  The "producer" task is the main Task while the
consumer task is started via `@async`.

```julia
using DataPipelineLocks

databuf = Ref(0)
pl = DataPipelineLock()

consumer = @async consume($pl, $databuf) do d
    result = 10 * d[] + 3
    println("pipeline result is $result")
end

producer = @async produce($pl, $databuf) do d
    d[] = rand(1:9)
end

wait(producer)
wait(consumer)
```

Normally the tasks in a data pipeline will loop many times to process multiple
blocks of data rather than perform a one-shot operation like the above example.
Here is a similar version that processes three "blocks" of data (where a "block"
here is the single `Int` stored in `databuf`):

```julia
using DataPipelineLocks

databuf = Ref(0)
pl = DataPipelineLock()

consumer = @async for i=1:3
    consume($pl, $databuf) do d
        result = 10 * d[] + 3
        println("pipeline result $i is $result")
    end
end

producer = @async for i=1:3
    produce($pl, $databuf) do d
        d[] = rand(1:9)
    end
end

wait(producer)
wait(consumer)
```