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
    DataPipelineLock(free=true) = new(Threads.Condition(), free)
end

# Implement AbstractLock methods
for f in (:islocked, :lock, :trylock, :unlock)
    @eval Base.$f(dpl::DataPipelineLock) = Base.$f(dpl.lock)
end

# Implement other Base methods
for f in (:wait, :notify)
    @eval Base.$f(dpl::DataPipelineLock) = Base.$f(dpl.lock)
end

# Provide a show method for DataPipelineLock
function Base.show(io::IO, dpl::DataPipelineLock)
    print(io, typeof(dpl), "@")
    show(io, UInt(pointer_from_objref(dpl)))
    print(io, dpl.free ? "(free)" : "(filled)")
end

"""
    isfree(dpl::DataPipelineLock) -> Bool
Retruns true if `dpl` is in the "free" state.
"""
isfree(dpl::DataPipelineLock) = dpl.free

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
        unlock(dpl)
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
