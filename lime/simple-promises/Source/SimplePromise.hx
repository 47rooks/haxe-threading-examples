package;

import haxe.Exception;
import haxe.Timer;
import haxe.ValueException;
import lime.app.Application;
import lime.app.Future;
import lime.app.Promise;
import lime.system.System;
import lime.ui.KeyCode;
import lime.ui.KeyModifier;

/**
 * SimplePromise demonstrates use of a Promise to update the state
 * of a Future. This is the purpose of a Promise and they are used
 * by Futures to drive Future updates from threads, or similarly 
 * in ThreadPools themselves.
 * 
 * Note that Promises are not themselves multi-threaded. They are a 
 * tool that can be used in threads to manipulate Futures.
 */
class SimplePromise extends Application {
	final TOTAL_ITERATIONS = 10;
	var promisesCreated = false;
	var promise:Promise<String>;
	var future:Future<String>;
	var iteration:Int;
	var raiseError:Bool = false;

	public function new() {
		super();
	}

	override public function update(deltaTime:Int):Void {
		super.update(deltaTime);

		/* Check termination condition. This is only for the demo
		 * as otherwise you have to go and shutdown the lime
		 * application window.
		 */
		if (future != null && (future.isComplete || future.isError)) {
			trace('All tasks completed. Exiting');
			System.exit(0);
		}

		/* If this is the first time through create the Promise
		 * and the timer function that will use it to update
		 * its Future.
		 */
		if (!promisesCreated) {
			promise = new Promise<String>();

			iteration = 0;
			future = promise.future;

			// Setup handler functions
			future.onComplete(promiseComplete);
			future.onProgress(promiseProgress);
			future.onError(promiseError);

			/* Create a closure over the Promise so it
			 * can report it progress and outcome through it.
			 * Note, if you breakpoint in a debugger in the
			 * timer.run function below, you will see that there
			 * is only one thread and that this function is 
			 * running in the main thread.
			 */
			var progress = 0;
			var total = 10;
			var timer = new Timer(1000);
			timer.run = function() {
				promise.progress(progress, total);
				progress++;

				if (raiseError) {
					promise.error(new ValueException('I got an error'));
				}

				if (progress == total) {
					promise.complete("Done!");
					timer.stop();
				}
			};

			promisesCreated = true;
		}
	}

	/**
	 * If you want to have the Promise cause the Future to error hit 'E'.
	 * @param key the Lime key keycode.
	 * @param modifier the Lime modifier key keycode.
	 */
	public override function onKeyUp(key:KeyCode, modifier:KeyModifier):Void {
		switch (key) {
			case E:
				raiseError = true;
			default:
		};
	}

	/**
	 * The Future completion handling function.
	 * 
	 * 
	 * @param result the result of the completed Future. Note, that there
	 * is an application level agreement on the type of the Promise's
	 * Future and the parameter to this function.
	 */
	function promiseComplete(result:String):Void {
		trace('COMPLETE: result is ${result}');
	}

	/**
	 * The progress handling function for the Promise's Future.
	 * 
	 * @param progress the amount of progress made.
	 * @param total the total progress that will be made by completion.
	 */
	function promiseProgress(progress:Int, total:Int):Void {
		trace('PROGRESS: ${progress} of ${total}');
	}

	/**
	 * The error handling function for the Promise's Future.
	 * 
	 * @param ex the exception. Note, that there is an application level
	 * agreement on the type of the errors that the Promise may raise
	 * and the parameter to this function. This is a Dynamic in the original
	 * API. Here we use an Exception but it could be anything.
	 */
	function promiseError(ex:Exception):Void {
		trace('ERROR: got exception ${ex}');
	}
}
