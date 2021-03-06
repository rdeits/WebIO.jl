type TestConn <: AbstractConnection
    msg
end

function Base.send(c::TestConn, msg)
    c.msg = msg
end

import WebIO: dispatch

@testset "communication" begin

    w = Scope("testctx1")

   #@test isa(instanceof(w), Scope)
   #@test instanceof(w).id == "testctx1"

    send(w, :msg_to_js, "hello js") # Queue a message to the JS side.
    @test take!(w.outbox) == Dict("type"=>"command",
                                  "scope"=>"testctx1",
                                  "command"=>:msg_to_js,
                                  "data"=>"hello js")
    
    send(w, :msg_to_js, "hello js again") # Queue it again

    conn = TestConn(nothing) # create a test connection

    # mimic front-end sending a _setup_scope special message
    # this message denotes that `conn` will be handling messages
    # to and from the scope with the given id
    dispatch(conn, Dict("command" => "_setup_scope",
                        "scope" => "testctx1"))

    yield() # allow a chance for ctx.outbox to write to connection

    # now ctx should have passed on its queued message to connection
    # in TestConn the message is simply stored in its msg ref field
    @test conn.msg == Dict("type"=>"command",
                           "command"=>:msg_to_js,
                           "scope"=>"testctx1",
                           "data"=>"hello js again")

    # further messages are sent freely
    send(w, :msg_to_js, "hello js a third time")
    yield()
    @test conn.msg == Dict("type"=>"command",
                           "command"=>:msg_to_js,
                           "scope"=>"testctx1",
                           "data"=>"hello js a third time")

    # mimic messages coming in from JS side

    # no scope named xx
    dispatch(conn, Dict("command" => "incoming",
                        "data"=>"hi Julia", "scope"=>"xx"))
    yield()
    # a warning was raised on receiving a message for an unknown
    # scope xx
    @test conn.msg["type"] == "log"
    @test contains(conn.msg["message"], "unknown scope xx")

    # this should give a warning
    dispatch(conn, Dict("command" => "incoming",
                        "data"=>"hi Julia", "scope"=>"testctx1"))

    msg = Ref("")
    on(x -> msg[] = x, w, "incoming") # setup the handler

    # dispatch message again
    dispatch(conn, Dict("command" => "incoming",
                        "data"=>"hi Julia!", "scope"=>"testctx1"))

    @test msg[] == "hi Julia!"
end


