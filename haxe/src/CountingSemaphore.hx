package;

import sys.thread.Lock;
import sys.thread.Mutex;
import sys.thread.Semaphore;
import sys.thread.Thread;

final ITERATIONS = 1000;

/**
 * Set the QUEUE_SIZE to 0 for an unlimited queue size.
 * Comparing the printed lengths with a 0 and a non-0 queue size.
 * 5 is a good example limit as the natural size is about 10-50 odd
 * on my machine but that will vary machine to machine. If you set
 * the limit you should not see a print of queue length above that.
 */
final QUEUE_SIZE = 0;

final MUTEXED = true;

/**
 * A multi-thread safe FIFO queue with optional size limiting.
 * 
 * This uses a regular Haxe Array<Int> and adds put() and get()
 * operations that provide FIFO behaviour protected by a mutex.
 * This makes addition and removal thread safe. It further will
 * enforce a size limit using counting semphores.
 */
class MTFIFOQueue {
	var _mutex = new Mutex(); // Mutex put and get operations
	var _q = new Array<Int>(); // the queue data
	var _sizeLimited:Bool = false;
	var _emptyCount:Semaphore; // count of currently empty slots
	var _fullCount:Semaphore; // count of currently occupied slots

	/**
	 * Create a new MT FIFO queue with optional size limited.
	 * @param maxSize the maximum size of the queue, 0 is unlimited
	 */
	public function new(?maxSize:Int = 0) {
		if (maxSize != 0) {
			_emptyCount = new Semaphore(maxSize);
			_fullCount = new Semaphore(0);
			_sizeLimited = true;
		}
	}

	/**
	 * Put an item into the queue at the head.
	 * If the size is limited and the queue is full the put
	 * operation will block until space becomes available.
	 * 
	 * @param value value to put in the queue.
	 */
	public function put(value:Int):Void {
		if (_sizeLimited) {
			_emptyCount.acquire();
		}

		if (MUTEXED)
			_mutex.acquire();

		_q.unshift(value);

		var l = _q.length;
		#if !hl // Only include this line if not HL due to hang bug
		trace('length of _q=${l}');
		#end

		// Verify that we do not exceed the QUEUE_SIZE
		// This is not functionally necessary in a queue but it is here
		// for demonstration purposes. If you disable the sizing semaphores
		// you will see this print.
		if (_sizeLimited && l > QUEUE_SIZE) {
			trace('queue length exceeded ' + QUEUE_SIZE + '. length=' + Std.string(l));
		}

		if (MUTEXED)
			_mutex.release();

		if (_sizeLimited)
			_fullCount.release();
	}

	/**
	 * Get the value from the tail of the queue.
	 * If there size is limited and there is no value this
	 * operation will block until there is a value available.
	 * 
	 * This may return null if the size is not limited and there
	 * is no value. This is a consequence of the fact that Array.pop()
	 * will return null if the queue is empty. This could be turned
	 * into a blocking wait too with a little more code if desired.
	 * 
	 * @return Null<Int> the value or in the none size limited case, null if
	 * there is no value in the queue.
	 */
	public function get():Null<Int> {
		if (_sizeLimited)
			_fullCount.acquire();

		if (MUTEXED)
			_mutex.acquire();

		var rv = _q.pop();

		if (MUTEXED)
			_mutex.release();

		if (_sizeLimited)
			_emptyCount.release();
		return rv;
	}
}

/**
 * The Consumer class reads values from the queue.
 * In this example the values are expected to be a sequence of numbers
 * from 0 going up in steps of 1. The Consumer verifies this. This is
 * strictly not necessary and even undesirable in some applications.
 * It is done here simply to verify that we are not dropping values.
 */
class Consumer {
	var _q:MTFIFOQueue;

	/**
	 * Create a Consumer with the specified queue.
	 * 
	 * @param q the queue to consume values from.
	 */
	public function new(q:MTFIFOQueue) {
		_q = q;
	}

	/**
	 * The consumer thread runs this method to pull values
	 * from the queue and verify we do not drop any.
	 */
	public function run():Void {
		var nextExpected = 0;
		var i = 0;
		while (i < ITERATIONS) {
			var rv = _q.get();

			if (rv != null) {
				if (nextExpected == rv) {
					nextExpected++;
				} else {
					trace('Terminating: missed value at i (${i}) expected (${nextExpected}) received (${rv})');
					return;
				}
				i++;
			}
		}
	}
}

/**
 * The Producer inserts values into the queue up to the
 * size limit of the queue if there is one. If not
 * it will put in as many as it can each time it is scheduled.
 */
class Producer {
	var _q:MTFIFOQueue;

	/**
	 * Create a Producer with the specified queue.
	 * 
	 * @param q the queue to publish values into.
	 */
	public function new(q:MTFIFOQueue) {
		_q = q;
	}

	/**
	 * The producer runs this mathod to publish values
	 * into the queue.
	 */
	public function run():Void {
		var next = 0;
		var i = 0;
		while (i++ < ITERATIONS) {
			_q.put(next++);
		}
	}
}

/**
 * Strictly speaking Haxe doesn't have a binary sempahore. It only has
 * counting semaphores. But it has a mutex which serves the same
 * purpose as a binary semaphore.
 * 
 * This example shows the use of a counting semaphore to synchronize a
 * producer consumer program.
 */
class CountingSemaphore {
	static public function main() {
		// The MT queue with the specified size.
		var q = new MTFIFOQueue(QUEUE_SIZE);

		// Create Producer and Consumer
		var p = new Producer(q);
		var c = new Consumer(q);

		// Create a lock instance so that main() knows
		// when the reader and writer are both done and
		// can exit.
		var l = new Lock();

		// Create threads to run
		var r = Thread.create(() -> {
			trace('Producer.run starting');
			p.run();
			trace('Producer.run ending');

			// Notify Main.main() that I am done
			l.release();
		});

		var w = Thread.create(() -> {
			trace('Consumer.run starting');
			c.run();
			trace('Consumer.run ending');

			// Notify Main.main() that I am done
			l.release();
		});

		// Wait for both threads to complete.
		l.wait();
		l.wait();
	}
}
