"""
    produce(f, dpl, args...; kwargs...)::Bool
Wait for `dpl` to be "free", call `f(args...; kwargs...)` which should
"produce" whatever data is needed to "fill" the "data buffer" associated with
`dpl`, and then sets `dpl` to the "filled" state.  Typically, `args` will
contain the "data buffer" to be filled.  Returns `false` if `dpl` is terminated,
otherwise returns `true`.
"""
function produce(f, dpl, args...; kwargs...)::Bool
    try
        @debug "produce >waitfree!" dpl
        waitfree!(dpl)
        @debug "produce <waitfree!" dpl

        f(args...; kwargs...)

        @debug "produce >setfilled!" dpl
        setfilled!(dpl)
        @debug "produce <setfilled!" dpl

        @debug "produce return true"
        return true
    catch ex
        # Rethrow a non-DataPipelineTerminated exception
        ex isa DataPipelineTerminated || rethrow()

        @debug "produce return false"
        return false
    end
end
