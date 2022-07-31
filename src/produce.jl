"""
    produce(f, pl, args...; kwargs...)
Waits for `pl` to be "free", calls `f(args...; kwargs...)` which should
"produce" whatever data is needed to "fill" the data buffer, and then sets `pl`
to the "filled" state.  Typically, `args` will contain the data buffer to be
filled.
"""
function produce(f, pl, args...; kwargs...)
    waitfree(pl)
    f(args...; kwargs...)
    setfilled!(pl)
end
