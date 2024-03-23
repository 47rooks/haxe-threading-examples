package;

import haxe.ValueException;
import lime.app.Application;
import lime.app.Future;
import lime.system.System;

/**
 * TaskState defines parameters to be passed to
 * the task function by Future.withEventualValue().
 */
typedef TaskState = {
	var fid:Int;
	var throwError:Bool;
}

/**
 * SimpleFutures is an application that shows a very simple
 * use of Lime Futures with a multi-threaded thread pool.
 * 
 * This queues NUM_TASKS tasks with up to MAX_THREADS threads
 * in the FutureWork pool. The tasks are trivially simple only
 * doing a sleep and emitting an integer. This is simply to 
 * make it clear that there are multiple threads running
 * concurrently as can be seen from the ordering of the traces.
 * All Futures set async to true. This approach to creating
 * futures in multi-threaded code is deprecated but, it is 
 * simpler to follow.
 * 
 * Note, while Future supports progress indication this requires
 * the use of a ThreadPool and will be taken up in another
 * example.
 */
class SimpleFutures extends Application {
	final MAX_THREADS = 5;
	final NUM_TASKS = 10;
	var jobsQueued = false; // Make sure we only queue the jobs once
	var numCompleted = 0;
	var numErrored = 0;

	public function new() {
		super();
	}

	override public function update(deltaTime:Int):Void {
		super.update(deltaTime);

		/* Check termination condition. This is only for the demo
		 * as otherwise you have to go and shutdown the lime
		 * application window.
		 */
		if ((numCompleted + numErrored) == NUM_TASKS) {
			trace('All tasks completed. Exiting');
			System.exit(0);
		}

		/* If this is the first time through then enqueue all
		 * the tasks. Note that the Future takes the actual work
		 * function as its first parameter.
		 * 
		 * To the Future is then added callbacks for completion and
		 * error handling. The completion and error handlers are
		 * called in the main thread. The work function itself is
		 * called in the threadpool thread.
		 */
		if (!jobsQueued) {
			FutureWork.maxThreads = MAX_THREADS;
			for (i in 0...NUM_TASKS) {
				var f = Future.withEventualValue(genNumber, {fid: i, throwError: i == (NUM_TASKS - 1) ? true : false});
				f.onComplete(futureComplete.bind(i));
				f.onError(futureError.bind(i));
			}

			jobsQueued = true;
		}
	}

	/**
	 * `genNumber` traces out some debug messages so it is easy to see
	 * what is happening. It then sleeps for a bit and prints another message
	 * before returning the final completion message.
	 * 
	 * @param fid this is a simple ID to track what is going on
	 * @param throwError if true this task will throw an exception
	 * @return String
	 */
	function genNumber(state:TaskState):String {
		trace('I am a thread starting ${state.fid}');

		/* Sleep a random amount - this will help alter thread progress
		 * which will show interleaving and concurrency more convincingly.
		 */
		Sys.sleep(Math.round(Math.random() * 5));
		if (state.throwError) {
			throw new ValueException('I hit an error');
		}
		trace('I am a thread completing ${state.fid}');
		return '${state.fid} completed';
	}

	/**
	 * Completion handling function
	 * @param futureId the future that called this function
	 * @param message the completed result from the task
	 */
	function futureComplete(futureId:Int, message:String) {
		trace('COMPLETE(${futureId}):Got int = ${message}');
		numCompleted++;
	}

	/**
	 * Error handling function.
	 * @param futureId the future that called this function
	 * @param error the error that was raised. Note that the
	 * error function must know how to handle whatever the
	 * `error` Dynamic is.
	 */
	function futureError(futureId:Int, error:Dynamic) {
		trace('ERROR(${futureId}):Got int from Future = ${error}');
		numErrored++;
	}
}
