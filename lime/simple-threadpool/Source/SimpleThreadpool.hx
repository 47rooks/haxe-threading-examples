package;

import haxe.Exception;
import haxe.Timer;
import haxe.ValueException;
import lime.app.Application;
import lime.system.System;
import lime.system.ThreadPool;
import lime.system.WorkOutput;

/**
 * The current state of the work function. This one is just used
 * for the input values. See `CancellableFibonacciState` for 
 * an example that stores intermediate state.
 */
@:structInit class FibonacciState {
	public var i1:Int; // Initial value 1
	public var i2:Int; // Initial value 2
}

/**
 * The current state of the work function. For cancellation to work
 * it is necessary for the function to return periodically. If it has
 * not been cancelled it will be called again with the same `State`
 * object so it can resume where it left off. In order for this to work
 * the job must stash its current state in this object before returning.
 */
@:structInit class CancellableFibonacciState {
	public var iteration:Int; // the current iteration
	public var partialResult:Array<Int>; // The current sequence values
}

/**
 * A custom error object if the job needs to return application specific
 * errors to the main thread.
 * The `onError()` function must understand this object.
 */
@:structInit class FibonacciError {
	public var id:Int; // Job id
	public var exception:Exception;
}

/**
 * A simple example progress object.
 * The `onProgress()` function must understand this object.
 */
@:structInit class FibonacciProgress {
	public var id:Int; // Job id
	public var iterationsCompleted:Int;
}

/**
 * This is the final result object. When the job completes it will
 * send one of these object via the `sendComplete()` function.
 * The `onComplete` function must understand this object.
 */
@:structInit class FibonacciResult {
	public var id:Int; // Job id
	public var sequence:Array<Int>;
}

/**
 * SimpleThreadPool attempts to explore the basic functions of ThreadPools
 * in running jobs. There are a number of jobs submitted all computing
 * the Fibonacci sequence. This is the work function, the function that
 * does the actual piece of work the application cares about. Now here all
 * threads do the same thing, while in a real application even if they all
 * used the same function they would likely use different data.
 * A more realistic example will follow now that this simple example has
 * gotten us used to how this framework works.
 *
 * This file is heavily commented so please read all the comments carefully
 * and hopefully it will all make sense.
 */
class SimpleThreadpool extends Application {
	/**
	 * The number of jobs to schedule.
	 * Note that the number should be > 4 as Job 3
	 * is used to show cancellation behaviour.
	 */
	final NUM_JOBS = 10;

	/**
	 * The maximum number of threads in the pool.
	 * Vary this number to see the impact on elapsed time
	 * of the run of all the jobs. A total elapsed time is 
	 * printed at the end.
	 */
	final MAX_THREADS = 10;

	/**
	 * The total number of iterations of the Fibonacci calculations.
	 * This is a trivial work function so the number of iterations
	 * needs to be high. A more complex function like the Sieve of
	 * Eratosthenes would no doubt have been a better choice for an
	 * example.
	 */
	final NUM_ITERATIONS = 10000000;

	/**
	 * In the job that throws an error, call sendError() with an
	 * exception if this is true, else simply throw a ValueException.
	 */
	final SEND_ERROR = false;

	/**
	 * Set this to true to use a properly cancellable work function.
	 * Refer to `computeFibonacci()` and `cancellableComputeFibonacci()`
	 * for details.
	 */
	final USE_CANCELLABLE_WORK_FUNCTION = true;

	/**
	 * If you want to see a print of the number of threads currently
	 * in the pool set this to true. It will of course impact overall
	 * runtime.
	 */
	final MONITOR_THREADS_IN_POOL = false;

	var _tp:ThreadPool;
	var jobsStarted:Bool = false;
	var jobsCompleted = 0;
	var sTime:Float;

	public function new() {
		super();
	}

	override public function update(deltaTime:Int):Void {
		super.update(deltaTime);

		/* Check termination condition. This is only for the demo
		 * as otherwise you have to go and shutdown the lime
		 * application window.
		 */
		if (jobsStarted && jobsCompleted == NUM_JOBS) {
			trace('All tasks completed. Exiting');
			var eTime = Timer.stamp();
			trace('End time=${eTime}');
			trace('Elapsed time=${eTime - sTime} seconds.');
			System.exit(0);
		}

		/**
		 * Kick off jobs only if this hasn't already been done.
		 * ThreadPool creation is done here because there is something
		 * about creating the pool in the constructor that leads to a
		 * null access exception. If that gets fixed I'll likely move this.
		 */
		if (!jobsStarted) {
			// Create threadpool and set handlers
			_tp = new ThreadPool(0, MAX_THREADS, MULTI_THREADED);
			_tp.onComplete.add(onComplete);
			_tp.onError.add(onError);
			_tp.onProgress.add(onProgress);

			/* Cache start time
			 * If you change the number of threads in the pool
			 * you can use the elapsed time print at the end of the
			 * run to see the effect of MT on the execution time.
			 */
			sTime = Timer.stamp();
			trace('Start time=${sTime}');
			for (i in 0...NUM_JOBS) {
				var jobId = -1;
				// This is where the job itself is scheduled
				if (USE_CANCELLABLE_WORK_FUNCTION) {
					var s:CancellableFibonacciState = {
						iteration: 0,
						partialResult: null
					};
					jobId = _tp.run(cancellableComputeFibonacci, s);
				} else {
					var s:FibonacciState = {i1: 1, i2: 1};
					jobId = _tp.run(computeFibonacci, s);
				}
				trace('jobid=${jobId} started');
			}
			jobsStarted = true;

			/* A quick example of cancelling a running job.
			 * this requires that job 3 run for more than 200 milliseconds.
			 * Note that, if you are running the computeFibonacci() work function
			 * that cancellation will not actually stop the thread. That is why
			 * job 3 outputs a message so that is obvious. If you use the
			 * cancellableComputeFibonacci() work function it should stop soon
			 * after the cancellation call is made.
			 */
			Timer.delay(() -> {
				trace('Timer cancelling job 3');
				_tp.cancelJob(3);
				jobsCompleted++;
			}, 200);
		}

		// Monitor number of active threads
		if (MONITOR_THREADS_IN_POOL) {
			trace('num of threads in pool=${_tp.currentThreads}');
		}
	}

	/**
	 * A basic Fibonacci sequence calculator.
	 * This also shows updating progress and throwing exceptions or
	 * sending errors with sendError().
	 * @param state the initial values to start the sequence at. Strictly 
	 * for a true Fibonacci there are both 1, but here we can pick what
	 * we want.
	 * @param output this is the WorkOutput object for communicating with
	 * the main thread.
	 */
	function computeFibonacci(state:FibonacciState, output:WorkOutput) {
		try {
			var rv = new Array<Int>();
			rv.push(state.i1);
			rv.push(state.i2);
			for (i in 0...NUM_ITERATIONS) {
				rv[i + 2] = rv[i] + rv[i + 1];

				if (output.activeJob.id == NUM_JOBS / 2 && i == NUM_ITERATIONS / 2) {
					if (SEND_ERROR) {
						output.sendError({id: output.activeJob.id, exception: new ValueException('computeFibonacci failed')});
						// After calling sendError() the job must terminate
						return;
					}
					throw new ValueException('ooops');
				}

				/* If this is jobid 3 then send progress reports every 5% of the way through
				 * the job. The reason for the trace is that it demonstrates that even when this
				 * job is cancelled it continues running. But while it continues running the
				 * sendProgress() messages are cut off by the framework so the main thread will
				 * not see these updates even though they are still being sent.
				 */
				if (output.activeJob.id == 3 && i % (NUM_ITERATIONS / 20) == 0) {
					var p:FibonacciProgress = {id: output.activeJob.id, iterationsCompleted: i};
					output.sendProgress(p);
					trace('It is me 3 !');
				}
			}

			// Send the final job completion output to the main thread.
			var c:FibonacciResult = {id: output.activeJob.id, sequence: rv};
			output.sendComplete(c);
		} catch (e:Dynamic) {
			trace('getting an error=$e');
			output.sendError(e);
		}
	}

	/**
	 * A basic Fibonacci sequence calculator.
	 * This version of the function shows how to make the job properly
	 * cancellable. It periodically updates its `State` and returns
	 * and restarts from where it left off until it finally completes.
	 * 
	 * @param state the initial values to start the sequence at. Strictly 
	 * for a true Fibonacci there are both 1, but here we can pick what
	 * we want.
	 * @param output this is the WorkOutput object for communicating with
	 * the main thread.
	 */
	function cancellableComputeFibonacci(state:CancellableFibonacciState, output:WorkOutput) {
		var rv = state.partialResult;
		if (rv == null) {
			// This is the first call to this work function, so initialize the sequence.
			rv = new Array<Int>();
			rv.push(1);
			rv.push(1);
		}
		for (i in state.iteration...NUM_ITERATIONS) {
			rv[i + 2] = rv[i] + rv[i + 1];

			/* If this is jobid 3 then send progress reports every 5% of the way through
			 * the job. The reason for the trace is that it demonstrates that when this
			 * job is cancelled it actually stops. This differs from `computeFibonacci()`
			 * which continues running.
			 */
			if (output.activeJob.id == 3 && i % (NUM_ITERATIONS / 20) == 0) {
				var p:FibonacciProgress = {id: output.activeJob.id, iterationsCompleted: i};
				output.sendProgress(p);
				trace('It is me 3 !');
			}

			/* Check for cancellation */
			if (i % (NUM_ITERATIONS / 20000) == 0) {
				// Stash the current state so we can restart.
				state.partialResult = rv;
				state.iteration = i + 1;
				return;
			}
		}

		// Send the final job completion output to the main thread.
		var c:FibonacciResult = {id: output.activeJob.id, sequence: rv};
		output.sendComplete(c);
	}

	/**
	 * This is the main thread completion function. It recieves the
	 * result that the thread pool thread sent via `sendCompletion()`.
	 *
	 * @param result the resulting Fibonacci sequence including all NUM_ITERATIONS + 2
	 * numbers.
	 */
	function onComplete(result:FibonacciResult):Void {
		trace('(COMPLETED) Job ${result.id} returned sequence starting at ${result.sequence[0]} and ending at ${result.sequence[result.sequence.length - 1]}');
		if (result.sequence.length != NUM_ITERATIONS + 2) {
			trace('Job ${_tp.activeJob.id} return the wrong number of elements (${result.sequence.length})');
		}
		jobsCompleted++;
	}

	/**
	 * This is the main thread error handling function. In this case it
	 * handles the custom FibonacciError structure or the regular Haxe exception.
	 *
	 * @param errorInfo this is a Dynamic and must be dynamically checked for correct
	 * handling, because there are two possibilities in this example.
	 */
	function onError(errorInfo:Dynamic):Void {
		trace('type=${Type.typeof(errorInfo)}, error=${errorInfo}');
		if (errorInfo is Exception) {
			trace('(ERROR) Job ${_tp.activeJob.id} Got exception ${Type.typeof(errorInfo)}:${errorInfo}');
		} else if (Reflect.hasField(errorInfo, 'id') && Reflect.hasField(errorInfo, 'exception')) {
			trace('(ERROR) Job ${_tp.activeJob.id} Got application error ${errorInfo.id}: ${errorInfo.exception}');
			trace('errorInfo=${errorInfo}');
		} else {
			trace('(ERROR) Job ${_tp.activeJob.id} Got unknown error type: ${errorInfo}');
		}
		jobsCompleted++;
	}

	/**
	 * This is the main thread progress function. This simply reports the number
	 * the job id and the number of iterations it has completed.
	 *
	 * @param progressInfo the custom progress object.
	 */
	function onProgress(progressInfo:FibonacciProgress):Void {
		trace('(PROGRESS) Job ${progressInfo.id}: ${progressInfo.iterationsCompleted}');
	}
}
