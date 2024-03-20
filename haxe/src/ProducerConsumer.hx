package;

import sys.thread.Lock;
import sys.thread.Semaphore;
import sys.thread.Thread;

/**
 * An very simple example of the classic producer consumer model
 * using semaphores.
 */
// Sempahore to indicate that a value has been produced
var produced = new Semaphore(0);

// Semphore to indicate that the value has been consumed
var consumed = new Semaphore(1);

// Buffer to pass the value between threads
var buffer = 0;
final NUM_ITERATIONS = 100;

/**
 * The Consumer simply waits for a new value to be produced
 * as indicated by the `produced` semaphore. Once it reads it
 * it just prints it out and indicates that it has consumed
 * the value via the `consumed` semaphore.
 */
class Consumer {
	public function new() {}

	public function run():Void {
		var i = 0;
		while (i++ < NUM_ITERATIONS) {
			produced.acquire();
			trace('CONSUMER:this is iteration ${i} and buffer contains ${buffer}');
			consumed.release();
		}
	}
}

/**
 * The Producer waits for the previous value to be consumed as
 * indicated by the `consumed` semaphore. It then publishes the
 * next value, and then indicates a new value has been published
 * by releasing the `produced` semaphore.
 */
class Producer {
	public function new() {}

	public function run():Void {
		var i = 0;
		while (i++ < NUM_ITERATIONS) {
			consumed.acquire();
			trace('PRODUCER:this is iteration ${i} and setting buffer to ${buffer}');
			buffer = i;
			produced.release();
		}
	}
}

/**
 * ProducerConsumer runs a very simple two thread producer consumer
 * example. The key things to note are the two semaphores and the
 * initial values of each. `produced` is initially 0 which will block
 * the Consumer until a value is produced. `consumed` is initially
 * 1 which allows the Producer to proceed immediately to publish the
 * initial value.
 * 
 * In the traces you should see that each process does one iteration and
 * waits for the other. The traces alternate between Producer and Consumer.
 * 
 * Note also, that while the buffer and semaphores are globals you would
 * not normally do it this way. A production implementation would
 * provide a way to pass the buffer and semaphores to the Producer and
 * Consumer.
 * 
 * Finally note also the Lock() object. This is used to prevent the
 * main thread from exiting before the other threads are finished.
 * If the main thread exits the program will end. This simple 
 * lock wait prevents that and each thread releases the lock when
 * it completes.
 */
class ProducerConsumer {
	public static function main() {
		var c = new Consumer();
		var p = new Producer();

		var l = new Lock();
		var tThread = Thread.create(() -> {
			trace('Consumer.run starting');
			c.run();
			trace('Consumer.run ending');

			// Notify Main.main() that I am done
			l.release();
		});

		var pThread = Thread.create(() -> {
			trace('Producer.run starting');
			p.run();
			trace('Producer.run ending');

			// Notify Main.main() that I am done
			l.release();
		});

		// Wait on threads to complete
		l.wait();
		l.wait();
	}
}
