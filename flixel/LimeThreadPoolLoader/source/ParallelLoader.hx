package;

import haxe.Exception;
import lime.graphics.Image;
import lime.system.ThreadPool;
import lime.system.WorkOutput;
import openfl.display.BitmapData;

/**
 * The current state of the work function. This simply contains the
 * path to the image to load. As this task is not interruptible, as it
 * is basically just a file read, there is no state to save.
 */
@:structInit class LoaderState
{
	public var imageToLoad:String; // Image to load
}

enum LoadedType
{
	BITMAP_DATA(img:BitmapData);
	IMAGE(img:Image);
}

/**
 * This is the final result object. When the job completes it will
 * send one of these object via the `sendComplete()` function.
 * The `onComplete` function must understand this object.
 */
@:structInit class LoaderResult
{
	public var imagePath:String; // Image to load
	public var img:LoadedType;
}

/**
 * Data structure reporting the progress of current load request. Only one
 * request may be active at a time, though this is not currently enforced.
 */
@:structInit class LoaderProgress
{
	public var numLoaded:Int;
	public var total:Int;
}

/**
 * Data structure reporting an error from the loading thread, including the
 * image that was being loaded and the error encountered.
 */
@:structInit class LoaderError
{
	public var imageToLoad:String; // path to image that failed to load
	public var error:String; // error message
}

/**
 * An example parallel asset loader for loading OpenFL BitmapData objects.
 * It uses a Lime ThreadPool for parallelisation.
 * An array of assets is loaded with one job being used per assets. Progress
 * may be reported on the basis of number of jobs completed (assets loaded)
 * against the number of assets to be loaded in total.
 */
class ParallelLoader
{
	var _numThreads:Int;
	var _tp:ThreadPool;
	var _loadImages:Bool;

	/* Progress metrics - only updated on the main application thread. Do
	 * not update these from the work function or you may see concurrency
	 * related issues, such as undercounting.
	 */
	var _numToLoad:Int;
	var _numLoaded:Int;

	var _completionCbk:(result:LoaderResult) -> Void;
	var _progressCbk:(progress:LoaderProgress) -> Void;
	var _errorCbk:(progress:LoaderError) -> Void;

	/**
	 * Constructor
	 * @param numThreads maximum number of threads in the pool.
	 * @param loadImages load lime.graphics.Images if true,
	 * openfl.display.BitmapData otherwise.
	 * @param completionCbk the completion callback to carry individual job load
	 * results back to the caller.
	 * @param progressCbk the progress callback to report the number of loads
	 * completed so far.
	 */
	public function new(numThreads:Int = 1, loadImages:Bool = true, completionCbk:(result:LoaderResult) -> Void = null,
			progressCbk:(progress:LoaderProgress) -> Void = null, errorCbk:(error:LoaderError) -> Void = null)
	{
		_numThreads = numThreads;
		_loadImages = loadImages;
		_completionCbk = completionCbk;
		_progressCbk = progressCbk;
		_errorCbk = errorCbk;

		// Create threadpool
		_tp = new ThreadPool(0, _numThreads, MULTI_THREADED);
		/* Register job completion and error callbacks. Progress is only
		 * reported at completion of each job, because it job reads a
		 * single asset from disk. So progress is reported at each job complete
		 * as a number of assets loaded vs the total number requested in
		 * the call to `load()`.
		 */
		_tp.onComplete.add(onComplete);
		_tp.onError.add(onError);
	}

	/**
	 * Load the assets in parallel.
	 * 
	 * Runs in: main application thread.
	 * 
	 * @param assetsToLoad a function that returns an Array of paths to
	 * assets to load.
	 */
	public function load(assetsToLoad:() -> Array<String>):Void
	{
		// Create jobs serially for loading each file
		var files = assetsToLoad();
		_numToLoad = files.length;
		_numLoaded = 0;
		for (f in files)
		{
			var s:LoaderState = {
				imageToLoad: f
			};
			if (_loadImages) {
				_tp.run(loadImage, s);
			} else {
				_tp.run(loadBitmapData, s);
			}
		}
	}

	/**
	 * Cancel outstanding jobs.
	 */
	public function cancel():Void
	{
		_tp.cancel();
	}

	/**
	 * Load an individual assets as a Lime Image.
	 * 
	 * Runs in: a threadpool thread.
	 * 
	 * @param state the loader state structure, which contains the file path
	 * to load.
	 * @param output the thread pool output object for communicating with
	 * the main application thread.
	 */
	function loadImage(state:LoaderState, output:WorkOutput):Void
	{
		var img = Image.fromFile(state.imageToLoad);
		if (img == null)
		{
			output.sendError({imageToLoad: state.imageToLoad, error: 'Image load failed'});
			return;
		}
		var result:LoaderResult = {imagePath: state.imageToLoad, img: LoadedType.IMAGE(img)};
		output.sendComplete(result);
	}

	/**
	 * Load an individual assets as an OpenFL BitmapData.
	 * 
	 * Runs in: a threadpool thread.
	 * 
	 * @param state the loader state structure, which contains the file path
	 * to load.
	 * @param output the thread pool output object for communicating with
	 * the main application thread.
	 */	function loadBitmapData(state:LoaderState, output:WorkOutput):Void
	{
		var bmd = BitmapData.fromFile(state.imageToLoad);
		if (bmd == null)
		{
			output.sendError({imageToLoad: state.imageToLoad, error: 'BitmapData load failed'});
			return;
		}
		var result:LoaderResult = {imagePath: state.imageToLoad, img: LoadedType.BITMAP_DATA(bmd)};
		output.sendComplete(result);
	}

	/**
	 * Completion callback for Lime ThreadPool.
	 * 
	 * Runs in: main application thread.
	 * 
	 * @param result The loader result to be passed on to the caller.
	 */
	function onComplete(result:LoaderResult)
	{
		// Send progress message
		_numLoaded++;
		if (_progressCbk != null)
		{
			var p:LoaderProgress = {numLoaded: _numLoaded, total: _numToLoad};
			_progressCbk(p);
		}
		// Report the completion
		if (_completionCbk != null)
			_completionCbk(result);
	}

	/**
	 * This is the main thread error handling function. In this case it
	 * handles the custom FibonacciError structure or the regular Haxe exception.
	 *
	 * Runs in: main application thread
	 * 
	 * @param errorInfo this is a Dynamic and must be dynamically checked for correct
	 * handling, because there are two possibilities in this example.
	 */
	function onError(errorInfo:Dynamic):Void
	{
		var error = "";
		trace('type=${Type.typeof(errorInfo)}, error=${errorInfo}');
		if (errorInfo is Exception)
		{
			error = '(ERROR) Job ${_tp.activeJob.id} Got exception ${Type.typeof(errorInfo)}:${errorInfo}';
			trace(error);
		}
		else if (Reflect.hasField(errorInfo, 'id') && Reflect.hasField(errorInfo, 'exception'))
		{
			trace('(ERROR) Job ${_tp.activeJob.id} Got application error ${errorInfo.id}: ${errorInfo.exception}');
			error = '${errorInfo}';
			trace('errorInfo=${error}');
		}
		else
		{
			error = '${errorInfo}';
			trace('(ERROR) Job ${_tp.activeJob.id} Got unknown error type: ${error}');
		}
		_numLoaded++;

		// Call the client error callback
		_errorCbk({
			imageToLoad: _tp.activeJob.state.imageToLoad,
			error: error
		});
	}

	public function getCurrentNumThreads():Int
	{
		return _tp.currentThreads;
	}

	public function getTotalImageToLoad():Int
	{
		return _numToLoad;
	}
}
