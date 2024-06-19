# Parallel Loader Example for HaxeFlixel

- [Parallel Loader Example for HaxeFlixel](#parallel-loader-example-for-haxeflixel)
  - [Background](#background)
  - [Know the Problem](#know-the-problem)
    - [Asset Loading in HaxeFlixel (HF)](#asset-loading-in-haxeflixel-hf)
  - [A Parallel Loader](#a-parallel-loader)
    - [From waffle to concrete](#from-waffle-to-concrete)
  - [Running the Example](#running-the-example)
    - [Steps](#steps)
      - [Running Serial](#running-serial)
      - [Reset](#reset)
      - [Parallel Loading](#parallel-loading)
  - [Some Results](#some-results)

## Background

This question comes up from time to time - how to speed up asset loads. In
general this isn't really a problem and people use various tricks like
preloaders and loading before the games, during scene switching and so on
to hide the load time. And on HTML5 async loads are possible. But it's a
interesting problem on sys targets. So I thought I would see what I could do
using a Lime ThreadPool to improve the overall load time for a bunch of assets.

Before I say anything, this is not a production ready solution. If it were I
would probably put it in a lib. But it provides a solid example of how to 
use a thread pool to do this sort of thing, and would be a good start on a
production version.

## Know the Problem

A lot of times a problem which seems to be a candidate for a MT solution and
people just dive in. But what problem are you actually going to solve, what
gets threaded, what remains on the main thread, and why. The first thing to 
determine is if you actually have a problem. So:

  * measure your asset load times
  * figure out if you can move the loads out of the fast path, like into a preloader
  * are your assets just too big

and likely other considerations.

Once you're convinced you have a problem and you think threading might help try to get a feel for what to thread and what benefit you might get. So with asset loading what can you parallelize and what can you not, and what benefit will you get.

So what is the most expensive part of loading an asset ? At this point you need to know basic ratios of things in computers. In loading images you have to allocate memory and read the bytes off the disk from the image file, decode the file format and put the bytes into the memory you allocated. In general, disk is slow, very slow. Even SSD is slow when compared to CPU cache line memory, or RAM. So it would be a fair guess that reading off disk is the slow bit. 

Next get some numbers. Performance problems are all about numbers. If the initial numbers are not bad enough there is not enough to gain by changing anything. I read an 8MB PNG off disk into a FlxSprite using `loadGraphic()` and it took over a second. This is an i7 with 16GB RAM and SSD storage. Hmmm.... After profiling a bit turns out PNG decoding is expensive. Cool - we learned something. My hardware is showing its age and there is a lot of time here which mean optimization might help - perhaps a lot.

### Asset Loading in HaxeFlixel (HF)

For the purpose of this example we will discuss only image assets and all comments here are made with that in mind.

Assets are loaded into a sprites basically via `FlxSprite.loadGraphic*` calls. But they are also loaded into a cache unless you explicitly tell it not to. A cache is generally a shared resource. If you modify a shared resource from multiple threads without concurrency controls you will have problems, random corruptions, lost writes, crashes and so on. Because of the way HF is written, being essentially single threaded there is no documentation of concurrency models and a huge amount of shared state. This just makes it ill-advised to parallelise `FlxSprite.loadGraphic*()` calls themselves. To do so safely goes beyond the scope of this example.

So let's look lower in the stack. HF sprites use OpenFL BitmapDatas for the image content. These can be loaded directly and then a BitmapData can be loaded into a FlxSprite. Now there is also caching in OpenFL so there could be issues here but we will have to see.

Finally, Lime also provides a way to load image data and in fact it's what the HF and OpenFL load routines use at the bottom. It is possible to load a Lime Image object directly from an a low level API and convert it into a BitmapData and that into a FlxSprite. The lower level routines don't necessarily use shared resources and so could very likely be implemented more safely.

A possible model. At this point we have two possible models to try out and to compare.

1. Load Lime Images in parallel and then convert those into BitmapData and FlxSprites serially on the main thread.
2. Load OpenFL BitmapDatas in parallel and then convert these into FlxSprites serially on the main thead.

Cool.

## A Parallel Loader

Ok so now we have a some numbers, some understanding of the problem, and some possible designs to try.

### From waffle to concrete

At this point you need to go and look and threading models and job pools and work queues and so on and see what kind of design you want. I'll save you the trouble for the minute and say that we are going to use the still unreleased Lime 8.2.0 ThreadPools. Of course, you'll go and research these things for yourself later, right ? Lime threadpools have been greatly enhanced and provide a job submission model with completion, error and progress callbacks. Refer to my https://github.com/47rooks/haxe-threading-examples/tree/main/lime/simple-threadpool for a simple example of how to use this.

In this part of the haxe-threading-examples repo then we have a `ParallelLoader.hx` class which uses Lime `ThreadPool` to provide a way to load assets in parallel. I won't detail it here. It is fully commented. But it supports configurable number of threads to use, and a choice of loading OpenFL BitmapDatas or Lime Images.

On the front of it there is a `PlayState.hx` which provides controls to select the number of threads, show the loading progress and provides simple timing display so you can create a list of comparative results. Performance - it's all about the data ! How often do I need to say that ?

## Running the Example

I do not supply any assets to load. You need to provide your own. Why ? Well every game or application is different and will have different assets and the improvement you get with one set will differ from that with another. Also, I don't want to bloat the repo with tons of test load resources.

When the app boots on the left are the controls and on the right there is an open area where thumbnails of the loaded assets are displayed.

Note, I've only actually run this on Windows, HL and CPP builds.

### Steps

   * Clone the repo
   * Build for either HashLink or CPP
   * Copy your test assets into `export\windows\bin\assets\images\tests` or `export\hl\bin\assets\images\tests`
     * You may need to create these directories
   * Run the executable using `lime run hl` or `lime run windows`

The actual UI is super primitive but should be obvious enough.

Bear in mind this is not a game and the loads are taking place in the loop which means the application may appear hung or unresponsive when long operations are being done on the main application thread. Proper integration of such operations into the game loop is left as an exercise for the reader, as they say.

#### Running Serial

Leave the `Number of threads` slider at 0 and hit the `Load` button. This will run a serial load on the main application thread. It does not use the ThreadPool at all. This will serve as a baseline measurement that you can compare different numbers of threads against. The `Load Time (seconds)` will show the time taken to load.

Run a number of runs of this ideally, exiting the app and restarting it each time. This will get rid of any unforeseen caching effects as much as possible. 

Finally note that the serial load does not update the progress bar because it is all done in one frame.

#### Reset

You can use the Reset button and do a new run but on HL memory is not properly deallocated, at least not in a timely way on Windows. I do not yet know why. I have logged an issue on this in case it is an HL GC issue but there is no final resolution on that yet. For the Windows CPP build this works ok and memory is released between runs. But I have seen another after several runs like this - a hang of some kind. This is yet to be investigated.

#### Parallel Loading

To run in parallel slide the `Number of threads` slider over to the number you want. Then select whether you want to load the assets as Lime Images, checked, or to load OpenFL BitmapDatas, unchecked. Then click Load.

The `Current Thread Count` will report the number of threads and the progress bar will indicate the proportion of assets loaded. The `Load Time (seconds)` will show the time taken to load.

Note, that the load time is the time from starting the load process to the point where all the FlxSprites have been created. It does not include the rendering time in the display of the loaded sprites.

Again do multiple runs and compare the loading as Image vs Bitmap and you can build up an understanding of how much benefit you may get from a parallel load.

## Some Results

Tested on MSI laptop with Intel(R) Core(TM) i7-7700HQ CPU @ 2.80GHz 2.80 GHz, 16GB RAM and a Samsung EVO 840 SSD, running Windows 10. Before testing the application was rebuilt in release mode on both HL and CPP. Relevant particularly to threading, the CPU has 4 hyper threaded cores - 8 threads of execution.

The data to be loaded was taken from FNF-PsychEngine merely grabbing all the PNGs. It does not necessarily represent a real load that would be done in a real game. It only serves to provide a set of data points to see how the loader behaves. For a test representative of your own situation you would need to use the set of resources you will load together.

|Target|# threads|Image or BitmapData|Load time (s)
|-|-|-|-|
|HL|Serial|N/A|22.08|
|HL|16|Image|12.056|
|HL|16|BitmapData|8.143|
|HL|64|Image|10.179|
|HL|64|BitmapData|6.402|
|cpp|Serial|N/A|22.337|
|cpp|16|Image|12.573|
|cpp|16|BitmapData|7.879|
|cpp|64|Image|11.331|
|cpp|64|BitmapData|7.797|

I will note that during the BitmapData load tests on cpp that there were what appeared to be two instances of hangs. This would suggest perhaps a concurrency problem in cpp when loading BitmapData. Image loading was fine. If there is a concurreny problem with BitmapData loads which I suspect due to caching it is likely that it is not entirely safe to use this loader mode. But it will take more investigation to determine for sure. Why HL does not hit it if there is such a problem is also unknown.

Also of note is that the cpp and HL load times are very similar HL beating cpp on a number of occasions. This was unexpected but interesting. It should als be noted that these were single runs for each data point. It would be better for a serious study to do multiple runs and average the results.