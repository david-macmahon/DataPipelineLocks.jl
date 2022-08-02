"""
    consume(f, dpl, args...; kwargs...)::Bool
Wait for `dpl` to be "filled", call `f(args...; kwargs...)` which should
"consume" whatever data is in the "data buffer", and then set `dpl` to the
"free" state.  Typically, `args` will contain the "data buffer" to be consumed.
Returns `false` if `dpl` is terminated, otherwise returns `true`.
"""
function consume(f, dpl, args...; kwargs...)::Bool
    try
        waitfilled(dpl)
        f(args...; kwargs...)
        setfree!(dpl)
        return true
    catch ex
        # Rethrow any non-DataPipelineTerminated exception
        ex isa DataPipelineTerminated || rethrow()
        return false
    end
end
