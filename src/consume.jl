"""
    consume(f, pl, args...; kwargs...)
Waits for `pl` to be "filled", calls `f(args...; kwargs...)` which should
"consume" whatever data is in the data buffer, and then sets `pl` to the "free"
state.  Typically, `args` will contain the data buffer to be consumed.
"""
function consume(f, pl, args...; kwargs...)
    waitfilled(pl)
    f(args...; kwargs...)
    setfree!(pl)
end
