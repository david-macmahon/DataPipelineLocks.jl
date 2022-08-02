"""
    propagate(f, dplsrc, dpldst, args...; kwargs...)::Bool
Wait for `dplsrc` to be "filled", wait for `dpldst` to be "free", call
`f(args...; kwargs...)` which should "propagate" (aka "process") data from the
source "data buffer" corresponding to `dplsrc` to the destination "data buffer"
corresponding to `dpldst`, and then set `dplsrc` to "free" and `dpldst` to
"filled".  Typically, `args` will contain the source and destination "data
buffers".  Returns `false` (after terminating `dpldst`) if `dplsrc` or `dpldst`
is terminated, otherwise returns `true`.
"""
function propagate(f, dplsrc, dpldst, args...; kwargs...)::Bool
    try
        waitfilled(dplsrc)
        waitfree(dpldst)
        f(args...; kwargs...)
        setfree!(dplsrc)
        setfilled!(dpldst)
        return true
    catch ex
        # Rethrow any non-DataPipelineTerminatedException exception
        ex isa DataPipelineTerminatedException || rethrow()
        # Propagate termination downstream
        terminate!(dpldst)
        return false
    end
end
