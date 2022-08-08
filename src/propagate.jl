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
        @debug "propagate >waitfilled!" dplsrc
        waitfilled!(dplsrc)
        @debug "propagate <waitfilled!" dplsrc

        @debug "propagate >waitfree!" dpldst
        waitfree!(dpldst)
        @debug "propagate <waitfree!" dpldst

        f(args...; kwargs...)

        @debug "propagate >setfilled!" dpldst
        setfilled!(dpldst)
        @debug "propagate <setfilled!" dpldst

        @debug "propagate >setfree!" dplsrc
        setfree!(dplsrc)
        @debug "propagate <setfree!" dplsrc

        @debug "propagate return true"
        return true
    catch ex
        # Rethrow any non-DataPipelineTerminated exception
        ex isa DataPipelineTerminated || rethrow()

        # Propagate termination downstream
        @debug "propagate >terminate!" dpldst
        terminate!(dpldst)
        @debug "propagate <terminate!" dpldst

        @debug "propagate return false"
        return false
    end
end
