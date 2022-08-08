"""
    consume(f, dpl, args...; kwargs...)::Bool
Wait for `dpl` to be "filled", call `f(args...; kwargs...)` which should
"consume" whatever data is in the "data buffer", and then set `dpl` to the
"free" state.  Typically, `args` will contain the "data buffer" to be consumed.
Returns `false` if `dpl` is terminated, otherwise returns `true`.
"""
function consume(f, dpl, args...; kwargs...)::Bool
    try
        @debug "consume >waitfilled" dpl
        waitfilled(dpl)
        @debug "consume <waitfilled" dpl

        f(args...; kwargs...)

        @debug "consume >setfree!" dpl
        setfree!(dpl)
        @debug "consume <setfree!" dpl

        @debug "consume return true"
        return true
    catch ex
        # Rethrow any non-DataPipelineTerminated exception
        ex isa DataPipelineTerminated || rethrow()

        @debug "consume return false"
        return false
    end
end
