"""
    propagate(f, dplsrc, dpldst, args...; kwargs...)
Wait for `dplsrc` to be "filled", wait for `dpldst` to be "free", call
`f(args...; kwargs...)` which should "propagate" (aka "process") data from the
source data buffer corresponding to `dplsrc` to the destination data buffer
corresponding to `dpldst`, and then set `plsrc` to "free" and `pldst` to
"filled".  Typically, `args` will contain the source and destination data
buffers.
"""
function propagate(f, dplsrc, dpldst, args...; kwargs...)
    waitfilled(dplsrc)
    waitfree(dpldst)
    f(args...; kwargs...)
    setfree!(dplsrc)
    setfilled!(dpldst)
end
