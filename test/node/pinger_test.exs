defmodule AnomaTest.Node.Pinger do
  use TestHelper.TestMacro, async: true

  alias Anoma.Node.{Mempool, Router, Pinger}
  alias Anoma.Node.Storage
  alias Anoma.Node.Ordering
  import TestHelper.Nock

  setup_all do
    storage = %Storage{
      qualified: AnomaTest.Pinger.Qualified,
      order: AnomaTest.Pinger.Order
    }

    name = :pinger
    snapshot_path = [:my_special_nock_snaphsot | 0]

    {:ok, nodes} =
      Anoma.Node.start_link_or_find_instance(
        name: name,
        use_rocks: false,
        testing: true,
        settings:
          {:new_storage,
           [
             snapshot_path: snapshot_path,
             storage_data: storage,
             block_storage: :pinger_blocks,
             ping_time: :no_timer
           ]
           |> Anoma.Node.start_min()}
      )

    node = Anoma.Node.state(nodes)

    [node: node]
  end

  test "Execution is done automatically", %{node: node} do
    key = 555
    storage = Ordering.get_storage(node.ordering)
    increment = increment_counter_val(key)
    zero = zero_counter(key)

    pinger = node.pinger

    ex_id = node.executor_topic.id
    mem_t = node.mempool_topic

    :ok =
      Router.call(
        node.router,
        {:subscribe_topic, ex_id, :local}
      )

    Mempool.hard_reset(node.mempool)

    Pinger.set_timer(pinger, 1)

    Pinger.start(pinger)

    :ok = Router.call(node.router, {:subscribe_topic, mem_t, :local})

    pid_zero = Mempool.tx(node.mempool, {:kv, zero}).pid

    assert_receive {:"$gen_cast", {_, _, {:submitted, _}}}

    pid_one = Mempool.tx(node.mempool, {:kv, increment}).pid
    pid_two = Mempool.tx(node.mempool, {:kv, increment}).pid

    assert_receive({:"$gen_cast", {_, _, {:process_done, ^pid_zero}}}, 5000)
    assert_receive({:"$gen_cast", {_, _, {:process_done, ^pid_one}}}, 5000)
    assert_receive({:"$gen_cast", {_, _, {:process_done, ^pid_two}}}, 5000)

    assert {:ok, 2} = Storage.get(storage, key)

    :ok =
      Router.call(
        node.router,
        {:unsubscribe_topic, ex_id, :local}
      )

    :ok =
      Router.call(
        node.router,
        {:unsubscribe_topic, mem_t, :local}
      )

    Anoma.Node.Pinger.set_timer(node.pinger, :no_timer)
  end
end
