package;

import sys.thread.Lock;
import sys.thread.Mutex;
import sys.thread.Semaphore;
import sys.thread.Thread;

final ITERATIONS = 1000;
final NUM_FREE_SLOTS = 10;
final SIZE_LIMITED = true;
final MUTEXED = true;

/**
 * A multi-thread safe FIFO queue.
 */
class MTFIFOQueue {
	var _mutex = new Mutex();
	var _q = new Array<Int>();

	public var length(get, null):Int;

	public function new() {}

	public function put(value:Int):Void {
		if (MUTEXED)
			_mutex.acquire();

		_q.unshift(value);

		if (MUTEXED)
			_mutex.release();
	}

	public function get():Int {
		if (MUTEXED)
			_mutex.acquire();

		var rv = _q.pop();

		if (MUTEXED)
			_mutex.release();
		return rv;
	}

	public function get_length():Int {
		return _q.length;
	}
}

class Consumer {
	var _emptyCount:Semaphore;
	var _fullCount:Semaphore;
	var _q:MTFIFOQueue;

	public function new(q:MTFIFOQueue, emptyCount:Semaphore, fullCount:Semaphore) {
		_q = q;
		_emptyCount = emptyCount;
		_fullCount = fullCount;
	}

	public function run():Void {
		var nextExpected = 0;
		var i = 0;
		while (i++ < ITERATIONS) {
			if (SIZE_LIMITED)
				_fullCount.acquire();

			var rv = _q.get();

			if (SIZE_LIMITED)
				_emptyCount.release();

			var l = _q.length;
			trace('length of _q=' + Std.string(l));
			// trace('length of _q=${l}');
			if (l > NUM_FREE_SLOTS) {
				trace('queue length exceeded ' + NUM_FREE_SLOTS + '. length=' + Std.string(l));
			}
			if (nextExpected == rv) {
				nextExpected++;
			} else {
				trace('Terminating: missed value at i (${i}) expected (${nextExpected}) received (${rv})');
				return;
			}
		}
	}
}

class Producer {
	var _emptyCount:Semaphore;
	var _fullCount:Semaphore;
	var _q:MTFIFOQueue;

	public function new(q:MTFIFOQueue, emptyCount:Semaphore, fullCount:Semaphore) {
		_q = q;
		_emptyCount = emptyCount;
		_fullCount = fullCount;
	}

	public function run():Void {
		var next = 0;
		var i = 0;
		while (i++ < ITERATIONS) {
			if (SIZE_LIMITED)
				_emptyCount.acquire();

			_q.put(next++);

			if (SIZE_LIMITED)
				_fullCount.release();
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
		// The semaphore records the number of free and full slots in the queue
		var emptyCount = new Semaphore(NUM_FREE_SLOTS);
		var fullCount = new Semaphore(0);
		var q = new MTFIFOQueue();

		// Create Producer and consumer using the same queue and semaphores
		var p = new Producer(q, emptyCount, fullCount);
		var c = new Consumer(q, emptyCount, fullCount);

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
