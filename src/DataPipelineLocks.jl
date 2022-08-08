module DataPipelineLocks

export DataPipelineLock
export DataPipelineTerminated
export getstate
export isfree, isfilled
export setfree!, setfilled!
export waitfree, waitfilled
export waitfree!, waitfilled!
export isterminated, terminate!
export produce, propagate, consume

include("lock.jl")
include("produce.jl")
include("propagate.jl")
include("consume.jl")

end # module DataPipelineLocks
