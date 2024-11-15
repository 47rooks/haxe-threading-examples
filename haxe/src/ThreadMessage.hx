package;

import sys.thread.Lock;
import sys.thread.Thread;

/**
 * Work is a simple work request message sent to a worker thread.
 */
typedef Work = {
	/**
	 * The id of the request. This is useful for tracking and debugging,
	 * for indicating which tasks failed and need retrying and so on.
	 */
	var id:Int;

	/**
	 * This is the thread to which a response must be sent.
	 * In a thread pool the submitter would just reap the response when it
	 * was ready. Here the thread needs to know where to send the response.
	 */
	var sender:Thread;

	/**
	 * This is the type of operation to perform. There are only two operations,
	 * ADD and STOP, in this example.
	 */
	var type:String;

	/**
	 * The first parameter for the task.
	 */
	var param1:Int;

	/**
	 * The second parameter for the task.
	 */
	var param2:Int;
}

/**
 * Response is a simple response message to the sender.
 */
typedef Response = {
	/**
	 * The task id for which this is the response. This allows the sender
	 * to match the response to its request.
	 */
	var id:Int;

	/**
	 * The type of the response. In this case there is only RESULT but in
	 * a normal system you would also need ERROR and possibly other types.
	 */
	var type:String;

	/**
	 * The result of the operation. This is only a Float type to permit
	 * other mathematical operations such as division.
	 */
	var result:Float;
}

/**
 * ThreadMessage is a simple demonstration of use of Thread sendMessage()
 * and readMessage() functions between threads. There is no error handling
 * and the work requests are trivial so load is simulated with Sys.sleep().
 */
class ThreadMessage {
	public static function main() {
		/* Create a worker thread that can respond to requests */
		var t = Thread.create(workerMain);

		// Call driver function in main thread
		driverMain(t);
	}

	/**
	 * This is the main driver function, basically the program main and
	 * it runs in the main haxe thread. It is a free-running while loop
	 * and thus if you watch this in a tool like Process Explorer or top
	 * you will see this thread consuming a whole hardware thread.
	 * 
	 * @param worker this is the worker thread to which requests can be sent.
	 * In a proper program this might well be done in a different way but
	 * passing it in directly is simple.
	 */
	static function driverMain(worker:Thread) {
		var exit = false;
		var numbers = [2, 2, 3, 4, 5, 6, 7, 8, 9, 1];
		var i = 0;
		var responseCount = 0;

		while (!exit) {
			// Enqueue work requests
			if (i < numbers.length / 2) {
				worker.sendMessage({
					id: i,
					sender: Thread.current(),
					type: 'ADD',
					param1: numbers[2 * i],
					param2: numbers[2 * i + 1]
				});
			}

			// Reap responses
			var r:Response = Thread.readMessage(false);
			if (r != null) {
				trace('At iteration ${i} got result for operation (${r.id}): ${r.result}');
				responseCount++;
			}

			// Exit condition
			if (responseCount >= numbers.length / 2) {
				exit = true;
			}

			i++;
		}
	}

	/**
	 * This is the worker main function. It runs in a separate thread which is
	 * started just after program start in main(). It could be started at any
	 * suitable time but for this demonstration that is the simplest.
	 * 
	 * It provides a simple blocking read message, do operation loop. The
	 * blocking read means the thread uses basically no cpu until there is
	 * work to do. In Process Explorer or top this thread will appear completely
	 * idle because it uses so little cpu. In a real application this would
	 * not be so.
	 * 
	 * Note, there is no error handling.
	 */
	static function workerMain():Void {
		var exit = false;
		while (!exit) {
			var m:Work = Thread.readMessage(true);
			switch m {
				case {type: "STOP"}:
					exit = true;
				case {
					id: id,
					sender: s,
					type: "ADD",
					param1: x,
					param2: y
				}:
					// Simulate time working
					Sys.sleep(Math.random());

					// Send computation result
					s.sendMessage({type: "RESULT", result: x + y, id: id});
				case _:
					trace('unknown message type');
			}
		}
	}
}
