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

    propagator = @async while true
        propagate($dpl1, $dpl2, $db1, $db2) do din, dout
            dout[] = 10 * din[]
        end
    end

    consumer = @async while true
        consume($dpl2, $db2, $dbout) do din, dout
            dout[] = din[] + 3
        end
    end

    # Give async tasks a chance to start
    yield()

    @test istaskstarted(propagator)
    @test !istaskdone(propagator)
    @test !istaskfailed(propagator)

    @test istaskstarted(consumer)
    @test !istaskdone(consumer)
    @test !istaskfailed(consumer)

    for i = 1:3
        d = rand(1:10)
        produce(dataref->dataref[]=d, dpl1, db1)

        waitfree(dpl1)
        waitfree(dpl2)
        @test dbout[] == 10 * d + 3
    end

    @test !istaskdone(propagator)
    @test !istaskfailed(propagator)

    @test !istaskdone(consumer)
    @test !istaskfailed(consumer)

    terminate!(dpl1)
    terminate!(dpl2)

    for t in (propagator, consumer)
        try
            wait(propagator)
            # Should never get here
            @test false
        catch ex
            @test ex isa TaskFailedException
            @test ex.task.result isa DataPipelineTerminatedException
        end
    end
end
