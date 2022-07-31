using DataPipelineLocks
using Test

@testset "DataPipelineLocks.jl" begin
    db1 = Ref(0)
    db2 = Ref(0)
    dbout = Ref(0)
    dpl1 = DataPipelineLock()
    dpl2 = DataPipelineLock()

    @test !islocked(dpl1)
    lock(dpl1)
    @test islocked(dpl1)
    unlock(dpl1)
    @test !islocked(dpl1)

    @test isfree(dpl2)
    @test !isfilled(dpl2)

    propagator = @async propagate($dpl1, $dpl2, $db1, $db2) do din, dout
        dout[] = 10 * din[]
    end

    consumer = @async consume($dpl2, $db2, $dbout) do din, dout
        dout[] = din[] + 3
    end

    # Give async tasks a chance to start
    yield()

    @test istaskstarted(propagator)
    @test !istaskdone(propagator)
    @test !istaskfailed(propagator)

    @test istaskstarted(consumer)
    @test !istaskdone(consumer)
    @test !istaskfailed(consumer)

    d = rand(1:10)
    produce(dataref->dataref[]=d, dpl1, db1)

    waitfree(dpl1)
    @test istaskstarted(propagator)
    @test istaskdone(propagator)
    @test !istaskfailed(propagator)

    waitfree(dpl2)
    @test istaskstarted(consumer)
    @test istaskdone(consumer)
    @test !istaskfailed(consumer)

    @test dbout[] == 10 * d + 3
end
