package;

import ParallelLoader.LoaderError;
import ParallelLoader.LoaderProgress;
import ParallelLoader.LoaderResult;
import flixel.FlxCamera;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxState;
import flixel.addons.ui.FlxSlider;
import flixel.addons.ui.FlxUIBar;
import flixel.addons.ui.FlxUICheckBox;
import flixel.group.FlxSpriteGroup;
import flixel.text.FlxText;
import flixel.ui.FlxBar;
import flixel.ui.FlxButton;
import flixel.util.FlxColor;
import haxe.Timer;
import haxe.ValueException;
import lime.graphics.Image;
import lime.system.System;
import openfl.display.BitmapData;
import sys.FileSystem;

class PlayState extends FlxState
{
	final IMAGES_DIR:String;
	final TEST_IMAGES_DIR:String;
	final MAX_THREADS = 256;

	var _controlsCamera:FlxCamera;
	var _controls:Controls;
	var _progressBar:FlxBar;
	var _currentThreads:FlxText;

	var _pl:ParallelLoader;

	var _title:FlxText;
	var _numThreads = 0;

	var _startTime:Float; // Starting time of the load
	var _endTime:Float; // Ending time of the load

	var _numimagesLoaded:Int;
	var _numLoadsErrored:Int;
	var _percentLoaded:Float;
	var _currentNumThreads:Float;
	var _numImagesToLoad:Float;
	var _loadTime:FlxText;
	var _loadJustCompleted:Bool = false;

	/**
	 * If checked load Lime Images, else load OpenFL BitmapData.
	 * Only applies to parallel loads
	 */
	var _loadImages:FlxUICheckBox;

	var _loadedImages:Array<Image>; // the loaded Lime Images
	var _loadedBitmapDatas:Array<BitmapData>; // the loaded OpenFL BitmapDatas
	var _loadedSprites:Array<FlxSprite>; // the loaded Sprites

	var _loadButton:FlxButton;
	var _resetButton:FlxButton;

	public function new()
	{
		super();
		IMAGES_DIR = 'assets/images';
		TEST_IMAGES_DIR = IMAGES_DIR + '/tests';
	}

	override public function create()
	{
		super.create();

		bgColor = FlxColor.CYAN;

		_title = new FlxText(Controls.LINE_X, 0, FlxG.width, "Parallel Loader Example", 48);
		_title.setFormat(null, 48, FlxColor.BLACK, FlxTextAlign.LEFT);
		add(_title);

		// Create a second camera for the controls so they will not be affected by filters.
		_controlsCamera = new FlxCamera(0, 0, FlxG.width, FlxG.height);
		_controlsCamera.bgColor = FlxColor.TRANSPARENT;
		FlxG.cameras.add(_controlsCamera, false);
		add(_controlsCamera);

		var numThreadsSlider = new FlxSlider(this, "_numThreads", Controls.LINE_X, 100.0, 0, MAX_THREADS, 450, 15, 3, FlxColor.BLACK, FlxColor.BLACK);
		numThreadsSlider.setTexts("Number of threads", true, "0", '${MAX_THREADS}', 12);

		_progressBar = new FlxUIBar(Controls.LINE_X, 170.0, LEFT_TO_RIGHT, 450, 15, this, "_percentLoaded", 0, 100, true);
		var progressBarName = new FlxText(Controls.LINE_X, 190.0, "Percentage of assets loaded", 12);
		progressBarName.setFormat(null, 12, FlxColor.BLACK, FlxTextAlign.LEFT);

		var currentThreadsLabel = new FlxText(Controls.LINE_X, 250.0, 200, "Current Thread Count", 12);
		currentThreadsLabel.setFormat(null, 12, FlxColor.BLACK, FlxTextAlign.LEFT);
		_currentThreads = new FlxText(Controls.LINE_X + 210, 250.0, "0", 12);
		_currentThreads.setFormat(null, 12, FlxColor.BLACK, FlxTextAlign.LEFT);

		var loadImagesLabel = new FlxText(Controls.LINE_X + 50, 280.0, 300, "Load lime.graphics.Image", 12);
		loadImagesLabel.setFormat(null, 12, FlxColor.BLACK, FlxTextAlign.LEFT);
		_loadImages = new FlxUICheckBox(Controls.LINE_X, 280, null, null, "", 100);
		_loadImages.checked = true;

		_loadButton = new FlxButton(Controls.LINE_X + 50, 310.0, "Load", _loadCbk);
		_resetButton = new FlxButton(Controls.LINE_X + 150, 310.0, "Reset", _resetCbk);

		var loadTimeLabel = new FlxText(Controls.LINE_X, 350.0, 200, "Load Time (seconds)", 12);
		loadTimeLabel.setFormat(null, 12, FlxColor.BLACK, FlxTextAlign.LEFT);
		_loadTime = new FlxText(Controls.LINE_X + 210, 350.0, "-", 12);
		_loadTime.setFormat(null, 12, FlxColor.BLACK, FlxTextAlign.LEFT);

		_controls = new Controls(20, 100, 550, 760, [

			// Add slider for the pixel box height
			numThreadsSlider,
			// Add progress bar
			_progressBar,
			progressBarName,
			// Add current thread count
			currentThreadsLabel,
			_currentThreads,
			// Load lime Images or openfl BitmapData
			_loadImages,
			loadImagesLabel,
			// Add buttons
			_loadButton,
			_resetButton,
			// Display the Load time
			loadTimeLabel,
			_loadTime
		], _controlsCamera);

		add(_controls._controls);
	}

	override public function update(elapsed:Float)
	{
		super.update(elapsed);

		if (_pl != null)
		{
			_currentNumThreads = _pl.getCurrentNumThreads();
			_currentThreads.text = '${_currentNumThreads}';
		}

		if (_loadJustCompleted)
		{
			// Compute load time. Note that this can be off by as
			// much as one frame time.
			_loadTime.text = '${_endTime - _startTime}';
			_renderLoadedSprites();
			_loadJustCompleted = false;
		}

		if (FlxG.keys.justReleased.ESCAPE)
		{
			// Cancel any remaining jobs in the thread pool if there is one
			if (_pl != null)
			{
				trace('cancelling tp');
				_pl.cancel();
			}
			// If you use Sys.exit() the application will hang. This is due
			// to issue https://github.com/openfl/lime/issues/1803. Until that
			// is resolved we use System.exit().
			System.exit(0);
			// Sys.exit(0);
		}
	}

	/**
	 * Load button callback. This initiates the load.
	 */
	function _loadCbk():Void
	{
		_loadButton.active = false;
		_doLoad();
	}

	/**
	 * Reset button callback. This resets the application for a new load.
	 */
	function _resetCbk():Void
	{
		trace('cache size=${_cacheSize()}');
		FlxG.resetState();
	}

	inline function _resetLoadMetrics():Void
	{
		_numimagesLoaded = 0;
		_numLoadsErrored = 0;
		_percentLoaded = 0.0;
		_startTime = 0.0;
		_endTime = 0.0;
		_loadJustCompleted = false;
	}

	function updateLoadProgress(total:Float):Void
	{
		// Update progress bar.
		if (_numimagesLoaded + _numLoadsErrored == total)
		{
			_percentLoaded = 100.0;
		}
	}

	/**
	 * The main load function.
	 * 
	 * For serial loads this function does the entire load.
	 * For parallel loads this functions creates a ParallelLoader which
	 * will perform the loads using a Lime ThreadPool.
	 */
	private function _doLoad():Void
	{
		_numimagesLoaded = 0;

		_loadedImages = new Array<Image>();
		_loadedBitmapDatas = new Array<BitmapData>();
		_loadedSprites = new Array<FlxSprite>();

		if (_numThreads == 0)
		{
			// Serial load in main thread
			trace('serial load start');

			_startTime = Timer.stamp();

			if (FileSystem.exists(TEST_IMAGES_DIR))
			{
				var imgToLoad = FileSystem.readDirectory(TEST_IMAGES_DIR);
				_numImagesToLoad = imgToLoad.length;
				for (inf in imgToLoad)
				{
					var fn = TEST_IMAGES_DIR + '/' + inf;

					var s = new FlxSprite();
					s.loadGraphic(fn);
					_loadedSprites.push(s);
					_numimagesLoaded++;
				}
			}

			_checkCompletion();
			_endTime = Timer.stamp();
		}
		else
		{
			// Parallel load with thread pool of numThreads threads
			trace('parallel load start');
			_currentNumThreads = 0;
			_currentThreads.text = '0';
			_startTime = Timer.stamp();
			_pl = new ParallelLoader(_numThreads, _loadImages.checked, _processResult, _reportProgress, _handleError);
			_pl.load(() ->
			{
				/**
				 * Append path to the actual asset name as Lime does
				 * not know anything about asset paths and must have
				 * a path relative to the current working directory.
				 */
				var rv = new Array<String>();
				for (p in FileSystem.readDirectory(TEST_IMAGES_DIR))
				{
					rv.push('${TEST_IMAGES_DIR}/${p}');
				}
				return rv;
			});
		}
	}

	/**
	 * Process the results from the ParallelLoader, as appropriate to the
	 * returned image type.
	 * 
	 * @param result the loader result which may contain BitmapDatas or Images.
	 */
	function _processResult(result:LoaderResult):Void
	{
		switch (result.img)
		{
			case BITMAP_DATA(i):
				_loadedBitmapDatas.push(i);
			case IMAGE(i):
				_loadedImages.push(i);
		}
		_numimagesLoaded++;
		_checkCompletion();
		if (_loadJustCompleted)
		{
			// In order to compare like with like times for parallel
			// and single threaded loads, we need to convert all
			// loaded Images to sprites here.
			for (img in _loadedImages)
			{
				var b = BitmapData.fromImage(img);
				var s = new FlxSprite().loadGraphic(b);
				_loadedSprites.push(s);
			}
			for (bmd in _loadedBitmapDatas)
			{
				var s = new FlxSprite().loadGraphic(bmd);
				_loadedSprites.push(s);
			}
			// Stamp completion time as soon as it is known
			_endTime = Timer.stamp();
		}
	}

	/**
	 * Populate the right hand half of the display with thumbnail images of
	 * the loaded sprites. This serves really only to demonstrate that the
	 * load worked and as a quick visual clue for any errors.
	 */
	function _renderLoadedSprites():Void
	{
		trace('rendering loaded sprites');
		var rowColCount = Math.ceil(Math.sqrt(_numimagesLoaded));
		final displayLEFT = 600;
		final displayTOP = 75;
		final displayRIGHT = FlxG.width - 50;
		final displayBOTTOM = FlxG.height - 50;

		var cellWidth = Math.ceil((displayRIGHT - displayLEFT) / rowColCount);
		var cellHeight = Math.ceil((displayBOTTOM - displayTOP) / rowColCount);
		for (i => s in _loadedSprites)
		{
			s.setGraphicSize(cellWidth, cellHeight);
			s.setSize(cellWidth, cellHeight);
			s.updateHitbox();

			s.x = displayLEFT + (i % rowColCount) * cellWidth;
			s.y = displayTOP + Math.floor(i / rowColCount) * cellHeight;
			add(s);
		}
	}

	/**
	 * Update the loader progress reporting to the UI.
	 * @param progress the loader progress including the number of assets
	 * to load in total and the number already loaded.
	 */
	function _reportProgress(progress:LoaderProgress):Void
	{
		_percentLoaded = progress.numLoaded * 100 / progress.total;

		// Strictly this only needs to be done once for a given load
		// but this will have to do for the demo.
		_numImagesToLoad = progress.total;
	}

	/**
	 * An example error handling function.
	 * A real error handler would have to figure out needed to be done
	 * to recover or retry. This merely updates the count of load errors
	 * and traces it out.
	 * 
	 * @param error the loader error object
	 */
	function _handleError(error:LoaderError):Void
	{
		_numLoadsErrored++;
		_checkCompletion();
		trace('Image load for ${error.imageToLoad} errored with ${error.error}');
	}

	/**
	 * Check for completion and set the just completed flag. The point here
	 * is that after the load completes we need to render the thumbnails but
	 * only want to do this once.
	 */
	function _checkCompletion():Void
	{
		if (_numImagesToLoad == _numLoadsErrored + _numimagesLoaded)
		{
			_loadJustCompleted = true;
		}
	}

	/**
	 * A little test function to check the bitmap cache size.
	 * @return Int the number of entries in the cache.
	 */
	@:access(flixel.system.frontEnds.BitmapFrontEnd._cache)
	inline function _cacheSize():Int
	{
		var numKeys = 0;
		for (k in FlxG.bitmap._cache.keys())
			numKeys++;
		return numKeys;
	}

	/**
	 * A little debug function to dump a stack trace at the current location.
	 * This is useful for figuring out how the code got to a certain point.
	 */
	function dumpStackAtCurrentLocation():Void
	{
		var ex = new ValueException('get a stack');
		trace('---- Current Stack START ----');
		#if hl
		trace('thread name: ${sys.thread.Thread.current().getName()}');
		#end
		trace(ex.stack);
		trace('---- Current Stack END ----');
	}
}

/**
 * Controls provide a sprite group which can contain a collection of controls
 * which can control the various aspects of the shader active in the demo.
 */
class Controls
{
	public static final LINE_X = 50;
	public static final BASE_FONT_SIZE = 16;

	public var _controls(default, null):FlxSpriteGroup;

	var _controlbg:FlxSprite;

	/**
	 * Create a new Controls object.
	 * @param xLoc the x position to place the group at.
	 * @param yLoc the y position to place the group at.
	 * @param xSize the width of the controls pane.
	 * @param ySize the height of the controls pane.
	 * @param uiElts an Array of FlxSprites to add to the control pane
	 */
	public function new(xLoc:Float, yLoc:Float, xSize:Int, ySize:Int, uiElts:Array<FlxSprite>, camera:FlxCamera)
	{
		// Put a semi-transparent background in
		_controlbg = new FlxSprite(10, 10);
		_controlbg.makeGraphic(xSize, ySize, FlxColor.BLUE);
		_controlbg.alpha = 0.2;
		_controlbg.cameras = [camera];

		_controls = new FlxSpriteGroup(xLoc, yLoc);
		_controls.cameras = [camera];

		_controls.add(_controlbg);

		// Add controls
		for (ui in uiElts)
		{
			ui.cameras = [camera];
			_controls.add(ui);
		}

		var returnPrompt = new FlxText(LINE_X, ySize - 40, "Hit <ESC> to exit", BASE_FONT_SIZE);
		returnPrompt.setFormat(null, 12, FlxColor.BLACK, FlxTextAlign.LEFT);
		_controls.add(returnPrompt);
	}

	/**
	 * Check if mouse overlaps the control area.
	 * @return Bool true if mouse overlaps control area, false otherwise.
	 */
	public function mouseOverlaps():Bool
	{
		return FlxG.mouse.overlaps(_controlbg);
	}
}
