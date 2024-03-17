package;

import haxe.Timer;
import sys.thread.Lock;
import sys.thread.Mutex;
import sys.thread.Thread;

/**
 * Enable or disable the use of the Data.mutex by the reader and writer classes.
 * If both are not enabled the reader will detect an inconsistency between
 * Data.x and Data.y, and exit.
 */
final USE_WRITE_MUTEX = true;

final USE_READ_MUTEX = true;
final ITERATIONS = 1000000;

/**
 * Data is a simple two value data structure which also contains a Mutex.
 */
class Data {
	public var mutex:Mutex;
	public var x:Int;
	public var y:Int;

	public function new() {
		mutex = new Mutex();
	}
}

/**
 * Example reader class which simpler reads the shared data object
 * and compares the x and y values. If they are the same then
 * we have a consistent Data object. If they are not then one was
 * updated after we read the first one and thus we have an incomplete
 * update, split write, corruption, whatever you want to call it.
 * 
 * Enable the use of the mutex on the critical section by setting the global
 * USE_READ_MUTEX to true.
 */
class Reader {
	var _d:Data;

	public function new(d:Data) {
		_d = d;
	}

	public function run(iterations:Int) {
		trace('Reader.run starting');
		while (iterations-- > 0) {
			// Read the data values unprotected and make sure they are the same
			// The values have to be copied into local variables so that the
			// trace statement does not have to read them again while the writer
			// is still updating.
			if (USE_READ_MUTEX) {
				_d.mutex.acquire();
			}
			var x = _d.x;
			var y = _d.y;
			if (USE_READ_MUTEX) {
				_d.mutex.release();
			}
			if (x != y) {
				trace('x (${x}) != y (${y}) differ at iteration ${ITERATIONS - iterations}');
				return;
			}
		}
		trace('Reader.run ending');
	}
}

/**
 * The Writer class generates a random number and sets both x and y in Data to 
 * that value.
 * 
 * Enable the use of the mutex on the critical section by setting the global
 * USE_WRITE_MUTEX to true.
 */
class Writer {
	var _d:Data;

	public function new(d:Data) {
		_d = d;
	}

	public function run(iterations:Int) {
		while (iterations-- > 0) {
			var r = Math.round(Math.random() * 100.0);
			if (USE_WRITE_MUTEX) {
				_d.mutex.acquire();
			}
			_d.x = r;
			_d.y = r;
			if (USE_WRITE_MUTEX) {
				_d.mutex.release();
			}
		}
	}
}

/**
 * Main runs a multithreaded test where the objective is
 * for the reader to see only matching Data.x and Data.y
 * while the writer changes the values to a new random
 * value each iteration.
 * 
 * Only with mutexing enabled will this actually pass 
 * through all iterations. Of course lowering the iteration
 * count will reduce the probability of failure but it won't
 * make it thread safe.
 */
class Main {
	public static function main() {
		var start = Timer.stamp();
		trace('Main starting at ${start}');

		// Create a data class
		var d = new Data();
		d.x = d.y = 0;

		// Create a Reader
		var reader = new Reader(d);

		// Create a Writer
		var writer = new Writer(d);

		// Create a lock instance so that main() knows
		// when the reader and writer are both done and
		// can exit.
		var l = new Lock();

		// Create two threads
		var r = Thread.create(() -> {
			trace('Reader.run starting');
			reader.run(ITERATIONS);
			trace('Reader.run ending');

			// Notify Main.main() that I am done
			l.release();
		});

		var w = Thread.create(() -> {
			trace('Writer.run starting');
			writer.run(ITERATIONS);
			trace('Writer.run ending');

			// Notify Main.main() that I am done
			l.release();
		});

		// Wait for both threads to complete.
		l.wait();
		l.wait();

		var end = Timer.stamp();
		trace('Main ending at ${end}');
		trace('elapsed=${end - start}');
	}
}
