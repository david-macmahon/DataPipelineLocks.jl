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

    propagator = @async while propagate($dpl1, $dpl2, $db1, $db2) do din, dout
        dout[] = 10 * din[]
    end
    end
    errormonitor(propagator)

    consumer = @async while consume($dpl2, $db2, $dbout) do din, dout
        dout[] = din[] + 3
    end
    end
    errormonitor(consumer)

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
        @test produce(dataref->dataref[]=d, dpl1, db1)

        # Wait for pipeline to flush
        waitfree(dpl1)
        waitfree(dpl2)

        @test dbout[] == 10 * d + 3
    end

    @test !istaskdone(propagator)
    @test !istaskfailed(propagator)

    @test !istaskdone(consumer)
    @test !istaskfailed(consumer)

    # Terminate first lock in the pipeline
    terminate!(dpl1)

    # Wait on the last task
    wait(consumer)

    @test istaskdone(propagator)
    @test istaskdone(consumer)
end
