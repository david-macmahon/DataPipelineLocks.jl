"""
A `DataPipelineTerminated` is thrown inside `wait` if the `DataPipelineLock` is
terminated while waiting.  The exception is also thrown if operation are
attempted on a terminated `DataPipelineLock`.
"""
struct DataPipelineTerminated <: Exception end

"""
`DataPipelineLockState` is an `Enum` used to represent the state of a
`DataPipelineLock`.  The five possible states are: `FREE`, `FILLING`, `FILLED`,
`DRAINING`, and `TERMINATED`.
"""
@enum DataPipelineLockState begin
    FREE
    FILLING
    FILLED
    DRAINING
    TERMINATED
end

"""
A `DataPipelineLock` is used to coordinate access to a data buffer between a
producer task and a consumer task.  The data buffer is considered to be in one
of five states, `FREE`, `FILLING`, `FILLED`, `DRAINING`, or `TWERMINATED` and
the data buffer's corresponding [`DataPipelineLockState`](@ref) tracks that
state.

- `FREE` - Data buffers and their locks start out in the `FREE` state.
  `DataPipelineLock`s in the `FREE` state are considered inactive until they are
  acquired by a task that will fill it.  A `DataPipelineLock` is considered
  acquired when [`waitfree`](@ref) returns (at which point the lock state will
  be `FILLING`).

- `FILLING` - Once [`waitfree`](@ref) returns, the lock is in the `FILLING`
  state which means that the acquiring task may populate the data buffer with
  data.  When the data buffer is fully populated, the task must change the state
  to `FILLED` by calling [`setfilled!`](@ref).

- `FILLED` - Data buffers in the `FILLED` state are ready for processing by a
  downstream task, but are not actively being processed.  Downstream tasks
  acquire filled data buffers by passing the data buffer's `DataPipelineLock`
  instance to [`waitfilled`](@ref).  Upon returning from [`waitfilled`](@ref),
  the data buffer is acquired for processing and its lock is in the `DRAINGING`
  state.

- `DRAINING` - Once [`waitfilled`](@ref) returns, the lock is in the `DRAINING`
  state which means that the acquiring task may process the data in the data
  buffer.  When the data in the buffer is fully processed, the task must change
  the state to `FREE` by calling [`setfree!`](@ref).

- `TERMINATED` - A `DataPipelineLock` instance may be terminated by calling the
  [`termiante!`](@ref) function.  Terminating a `DataPipelineLock` causes a
  [`DataPipelineLockTerminated`](@ref) exception to be thrown in each task that
  is currently waiting on the lock.  Any future `waitfree` or `waitfilled` calls
  on the lock will also throw this exception.  Tasks that wait on a
  `DataPipelineLock` should be prepared to catch this exception and respond by
  terminating any downstream locks that it is using.  This allows for a pipeline
  to be terminated by terminating the output locks of the first task.

The higher-level functions `produce`, `propagate`, and `consume` are usually
used instead of the lower level synchronization and state related functions,
except in cases where more flexibility is needed.

`DataPipelineLock` does not specify the nature of the "data buffer".  Nor does
it even know what the "data buffer" is or where it lives (e.g. CPU vs GPU).
"""
mutable struct DataPipelineLock <: Base.AbstractLock
    lock::Threads.Condition
    state::DataPipelineLockState
    DataPipelineLock(state=FREE) = new(Threads.Condition(), state)
end

"""
    throw_if_terminated(dpl)
Throws a `DataPipelineTerminated` if `dpl` has been terminated.
"""
function throw_if_terminated(dpl::DataPipelineLock)
    isterminated(dpl) && throw(DataPipelineTerminated())
end

"""
    terminate!(dpl)
Terminate the given `DataPipelineLock`.  This puts `dpl` in the `TERMINATED`
state and wakes all waiters with a `DataPipelineTerminated` exception.
Most operations on `DataPipelineLock` instances in the terminated state will
also throw the same exception type.  Terminating an already terminated lock is
allowed and does nothing.
"""
function terminate!(dpl::DataPipelineLock)
    # Terminating a terminated DataPipelineLock is a no-op
    isterminated(dpl) && return dpl

    lock(dpl)
    try
        dpl.state = TERMINATED
        Base.notify_error(dpl.lock, DataPipelineTerminated())
    finally
        # Cannot call `unlock(dpl)` because `dpl` is now terminated!
        unlock(dpl.lock)
    end
    dpl
end

# Implement AbstractLock methods
for f in (:islocked, :lock, :trylock, :unlock)
    @eval function Base.$f(dpl::DataPipelineLock)
        throw_if_terminated(dpl)
        $f(dpl.lock)
    end
end

# Implement Base.wait for DataPipelineLock
function Base.wait(dpl::DataPipelineLock)
    # Check whether `dpl` is already terminated
    throw_if_terminated(dpl)

    wait(dpl.lock)

    # Check whether `dpl` is newly terminated
    throw_if_terminated(dpl)
end

# Implement Base.notify
Base.notify(dpl::DataPipelineLock, @nospecialize(arg=nothing); all=true, error=false) = notify(dpl.lock, arg, all, error)
Base.notify(dpl::DataPipelineLock, @nospecialize(arg), all, error) = notify(dpl.lock, arg, all, error)

# Provide a show method for DataPipelineLock
function Base.show(io::IO, dpl::DataPipelineLock)
    print(io, typeof(dpl), "@")
    show(io, UInt(pointer_from_objref(dpl)))
    print(io, "(", dpl.state, ")")
end

"""
    getstate(dpl::DataPipelineLock) -> DataPipelineLockState
Return the current state of `dpl`.
"""
getstate(dpl::DataPipelineLock) = dpl.state

"""
    isstate(dpl::DataPipelineLock, state::DataPipelineLockState) -> Bool
Return true if `dpl` is in the `state` state.  Throw a
`DataPipelineLockTerminated` exception if the lock has been terminated unless
`state` is `TERMINATED`.
"""
function isstate(dpl::DataPipelineLock, state::DataPipelineLockState)
    # If testing for TERMINATED, don't throw if terminated
    state != TERMINATED && throw_if_terminated(dpl)
    dpl.state === state
end

"""
    isfree(dpl::DataPipelineLock) -> Bool
Return true if `dpl` is in the `free` state.  Throw a
`DataPipelineLockTerminated` exception if the lock has been terminated unless
`state` is `TERMINATED`.
"""
isfree(dpl::DataPipelineLock) = isstate(dpl, FREE)

"""
    isfilling(dpl::DataPipelineLock) -> Bool
Return true if `dpl` is in the `FILLING` state.  Throw a
`DataPipelineLockTerminated` exception if the lock has been terminated.
"""
isfilling(dpl::DataPipelineLock) = isstate(dpl, FILLING)

"""
    isfilled(dpl::DataPipelineLock) -> Bool
Return true if `dpl` is in the `filled` state.  Throw a
`DataPipelineLockTerminated` exception if the lock has been terminated.
"""
isfilled(dpl::DataPipelineLock) = isstate(dpl, FILLED)

"""
    isdraining(dpl::DataPipelineLock) -> Bool
Return true if `dpl` is in the `DRAINING` state.  Throw a
`DataPipelineLockTerminated` exception if the lock has been terminated.
"""
isdraining(dpl::DataPipelineLock) = isstate(dpl, DRAINING)

"""
    isterminated(dpl) -> Bool
Return true if `dpl` has been terminated, otherwise false.
"""
isterminated(dpl) = isstate(dpl, TERMINATED)

"""
    wait(dpl::DataPipelineLock, state::DataPipelineLockState; acquire=true)
Wait for `dpl` to have the state specified by `state`.  If `state` is `FREE` or
`FILLED` and `acquire` is `true`, the lock's state will be changed to `FILLING`
or `DRAINING`, respectively, once the lock is acquired.
"""
function waitstate(dpl::DataPipelineLock, state::DataPipelineLockState, acquire=true)
    lock(dpl)
    try
        while dpl.state != state
            wait(dpl)
        end
        # We got lock in the desired state!
        # Transition to next state as needed (no need to notify anyone)
        acquire && state === FREE   && (dpl.state = FILLING)
        acquire && state === FILLED && (dpl.state = DRAINING)
    finally
        # Call `unlock(dpl.lock)` rather than `unlock(dpl)` because `dpl` could
        # have been terminated in `wait`.
        unlock(dpl.lock)
    end
    dpl
end

"""
    waitfree!(dpl::DataPipelineLock)
Waits for `dpl` to be `FREE` and then atomically transition `dpl` to the
`FILLING` state.  This is the method used by `produce` and `propagate`.  Custom
producer or propagator tasks that do not use those functions should call
`waitfree!` to acquire `dpl` with atomic transition into the `FILLING` state.
To wait for `dpl` to be `FREE` without transitioning to `FILLING` see
[`waitfree`](@ref).
"""
waitfree!(dpl::DataPipelineLock) = waitstate(dpl, FREE, true)

"""
    waitfree(dpl::DataPipelineLock)
Waits for `dpl` to be `FREE` without transitioning `dpl` to the `FILLING` state.
This method can be used to monitor the state of a `DataPipelineLock` without
impacting the lock itself.  To wait for `dpl` to be `FREE` and then atomically
transition to `FILLING` see [`waitfree!`](@ref).
"""
waitfree(dpl::DataPipelineLock) = waitstate(dpl, FREE, false)

#= Not sure this is useful enough to implement
"""
    waitfilling(dpl::DataPipelineLock)
Waits for `dpl` to be `FILLING`.
"""
waitfilling(dpl::DataPipelineLock) = waitstate(dpl, FILLING)
=#

"""
    waitfilled!(dpl::DataPipelineLock)
Waits for `dpl` to be filled.
Waits for `dpl` to be `FILLED` and then atomically transition `dpl` to the
`DRAINING` state.  This is the method used by `propagate` and `consume`.  Custom
propagator or consumer tasks that do not use those functions should call
`waitfillled!` to acquire `dpl` with atomic transition into the `DRAINING`
state.  To wait for `dpl` to be `FILLED` without transitioning to `DRAINING` see
[`waitfilled`](@ref).
"""
waitfilled!(dpl::DataPipelineLock) = waitstate(dpl, FILLED, true)

"""
    waitfilled(dpl::DataPipelineLock)
Waits for `dpl` to be `FILLED` without transitioning `dpl` to the `DRAINING`
state.  This method can be used to monitor the state of a `DataPipelineLock`
without impacting the lock itself.  To wait for `dpl` to be `FILLED` and then
atomically transition to `DRAINING` see [`waitfilled!`](@ref).
"""
waitfilled(dpl::DataPipelineLock) = waitstate(dpl, FILLED, false)

#= Not sure this is useful enough to implement
"""
    waitdraining(dpl::DataPipelineLock)
Waits for `dpl` to be `DRAINING`.
"""
waitdraining(dpl::DataPipelineLock) = waitstate(dpl, DRAINING)
=#

"""
    setstate!(dpl::DataPipelineLock, state::DataPipelineLockState)
In a thread-safe manner, set the state of `dpl` to `state` and then call
`notify` on `dpl` to inform any waiting task of the state change.  Cannot be
used to set the state to `TERMINATED`, use [`terminate!`](@ref) to do that.
Only `FILLING=>FILLED` and `DRAINING=>EMPTY` transitions are allowed, any other
transition will throw an exception.
"""
function setstate!(dpl::DataPipelineLock, state::DataPipelineLockState)
    lock(dpl)
    try
        # If this is a supported transition
        if (dpl.state == FILLING  && state == FILLED) ||
           (dpl.state == DRAINING && state == FREE)
            # Update state and notify
            dpl.state = state
            notify(dpl)
        else
            m = "cannot setstate! from $(dpl.state) to $(state)"
            @error m
            error(m)
        end
    finally
        unlock(dpl)
    end
    dpl
end

"""
    setfree!(dpl::DataPipelineLock)
In a thread-safe manner, set the state of `dpl` to `FREE` and notify any waiting
task.
"""
setfree!(dpl::DataPipelineLock) = setstate!(dpl, FREE)

"""
    setfilled!(dpl::DataPipelineLock)
In a thread-safe manner, set the state of `dpl` to `FILLED` and notify any
waiting task.
"""
setfilled!(dpl::DataPipelineLock) = setstate!(dpl, FILLED)
