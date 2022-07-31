module DataPipelineLocks

export DataPipelineLock
export isfree, isfilled
export setfree!, setfilled!
export waitfree, waitfilled
export produce, propagate, consume

include("lock.jl")
include("produce.jl")
include("propagate.jl")
include("consume.jl")

end # module DataPipelineLocks
