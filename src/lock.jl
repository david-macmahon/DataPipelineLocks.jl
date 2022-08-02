"""
A `DataPipelineTerminatedException` is thrown inside `wait` if the
`DataPipelineLock` is terminated while waiting.  The exception is also thrown if
operation are attempted on a terminated `DataPipelineLock`.
"""
struct DataPipelineTerminatedException <: Exception end

"""
A `DataPipelineLock`` is used to coordinate access to a data buffer between a
producer task and a consumer task.  The data buffer is considered to be either
*free* or *filled* and this state is tracked in the `DataPipelineLock`.  When in
the *free* state, the producer may modify the contents of the data buffer.  When
in the *filled* state, the producer must not modify the contents of the data
buffer.  While in the *free* state, the data buffer contents must not be used by
the consumer.  While in the *filled* state, the data buffer must not be modified
(or otherwise used) by the producer.  Once a producer has completed producing
data into the buffer, it should set the state of the `DataPipelineLock` to
*filled* via the `setfilled` function.  Once a consumer has completed consuming
the data from the buffer it should set the state of the `DataPipelineLock` to
*free* via the `setfree` function.

The higher level functions `produce`, `propagate`, and `consume` are usually
used instead of the lower level synchronization and state related functions,
except in cases where more flexibility is needed.

`DataPipelineLock` does not specify the nature of the "data buffer".  Nor does it
even know what the "data buffer" is or where it lives.
"""
mutable struct DataPipelineLock <: Base.AbstractLock
    lock::Threads.Condition
    free::Bool
    terminated::Bool
    DataPipelineLock(free=true) = new(Threads.Condition(), free, false)
end

"""
    isterminated(dpl) -> Bool
Return true if `dpl` has been terminated, otherwise false.
"""
isterminated(dpl) = dpl.terminated

"""
    check_terminated(dpl)
Throws a `DataPipelineTerminatedException` if `dpl` has been terminated.
"""
function check_terminated(dpl::DataPipelineLock)
    isterminated(dpl) && throw(DataPipelineTerminatedException())
end

"""
    terminate!(dpl)
Terminates the given `DataPipelineLock`.  This wakes all waiters with a
`DataPipelineTerminatedException` and puts `dpl` in the *terminated* state.
Operations on `DataPipelineLock` instances in the terminated state will also
throw the same exception type.
"""
function terminate!(dpl::DataPipelineLock)
    lock(dpl)
    try
        dpl.terminated = true
        Base.notify_error(dpl.lock, DataPipelineTerminatedException())
    finally
        # Cannot call `unlock(dpl)` because `dpl` is now terminated!
        unlock(dpl.lock)
    end
    dpl
end

# Implement AbstractLock methods
for f in (:islocked, :lock, :trylock, :unlock)
    @eval function Base.$f(dpl::DataPipelineLock)
        check_terminated(dpl)
        $f(dpl.lock)
    end
end

# Implement Base.wait for DataPipelineLock
function Base.wait(dpl::DataPipelineLock)
    # Check whether `dpl` is already terminated
    check_terminated(dpl)

    wait(dpl.lock)

    # Check whether `dpl` is newly terminated
    check_terminated(dpl)
end

# Implement Base.notify
Base.notify(dpl::DataPipelineLock, @nospecialize(arg=nothing); all=true, error=false) = notify(dpl.lock, arg, all, error)
Base.notify(dpl::DataPipelineLock, @nospecialize(arg), all, error) = notify(dpl.lock, arg, all, error)

# Provide a show method for DataPipelineLock
function Base.show(io::IO, dpl::DataPipelineLock)
    print(io, typeof(dpl), "@")
    show(io, UInt(pointer_from_objref(dpl)))
    print(io, dpl.free ? "(free)" : "(filled)")
    dpl.terminated && print(io, "[terminated]")
end

"""
    isfree(dpl::DataPipelineLock) -> Bool
Retruns true if `dpl` is in the "free" state.
"""
function isfree(dpl::DataPipelineLock)
    check_terminated(dpl)
    dpl.free
end

"""
    isfilled(dpl::DataPipelineLock) -> Bool
Retruns true if `dpl` is in the "filled" state.
"""
isfilled(dpl::DataPipelineLock) = !isfree(dpl)

"""
    wait(dpl::DataPipelineLock, freestate::Bool)
Waits for `dpl` to have the free state specified by `freestate`.
"""
function Base.wait(dpl::DataPipelineLock, freestate::Bool)
    lock(dpl)
    try
        while dpl.free != freestate
            wait(dpl)
        end
    finally
        # Call `unlock(dpl.lock)` because `dpl` could be newly terminated!
        unlock(dpl.lock)
    end
end

"""
    waitfree(dpl::DataPipelineLock)
Waits for `dpl` to be free.
"""
waitfree(dpl::DataPipelineLock) = wait(dpl, true)

"""
    waitfilled(dpl::DataPipelineLock)
Waits for `dpl` to be filled.
"""
waitfilled(dpl::DataPipelineLock) = wait(dpl, false)

"""
    setstate!(dpl::DataPipelineLock, freestate::Bool)
In a thread-safe manner, set the free state of `dpl` to `freestate` and then
call `notify` on `dpl` to inform any waiting task.
"""
function setstate!(dpl::DataPipelineLock, freestate::Bool)
    lock(dpl)
    try
        if dpl.free == freestate
            @warn "DataPipelineLock is already $(freestate ? "free" : "filled")"
        end
        dpl.free = freestate
        notify(dpl)
    finally
        unlock(dpl)
    end
end

"""
    setfree!(dpl::DataPipelineLock)
In a thread-safe manner, set the state of `dpl` to "free" and notify any waiting
task.
"""
setfree!(dpl::DataPipelineLock) = setstate!(dpl, true)

"""
    setfilled!(dpl::DataPipelineLock)
In a thread-safe manner, set the state of `dpl` to "filled" and notify any
waiting task.
"""
setfilled!(dpl::DataPipelineLock) = setstate!(dpl, false)
