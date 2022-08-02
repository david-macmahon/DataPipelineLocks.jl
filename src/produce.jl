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
        waitfree(dpl)
        f(args...; kwargs...)
        setfilled!(dpl)
        return true
    catch ex
        # Rethrow a non-DataPipelineTerminated exception
        ex isa DataPipelineTerminated || rethrow()
        return false
    end
end
