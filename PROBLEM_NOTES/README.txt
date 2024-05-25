**** I tried this on GHC 9.8.2 and the issue WAS NOT THERE. It seems it was fixed in the last ~4 years.
Regardless, the files to read the inlining binaries for GHC 9.8.2 are in PROBLEM_NOTES/NEWER_GHC_FILES. 
To build on that version of GHC, they just need to be copied over, add GNNUtils to the Exposed Modules, 
and build with hadrian.



----------------------------- Instructions below. I will make this repo private again until after publication,
----------------------------- when I'll make a public artifact.


HOW TO REPRODUCE:

1. Build compiler.
    (Small instruction. Lengthy task.)

2. Get the source code for loop-0.3.0
    For example:

    curl https://hackage.haskell.org/package/loop-0.3.0/loop-0.3.0.tar.gz -o loop-0.3.0.tar.gz
    tar -xvf loop-0.3.0.tar.gz

    cd loop-0.3.0

3. Build and time loop-0.3.0 with and without the binary to compare.

    To see the time without the binary:
        time (cabal new-test all --with-compiler=/home/celeste/GHCs/ghc_inlining_research/inplace/bin/ghc-stage2)
    
    Note that not passing a flag for the binary will make GHC build normally.
    Execute the command twice to rule out compilation time, of course.
    
    To see the time with the binary:
        time (cabal new-test all --with-compiler=<path/to/compiler>/ghc-stage2 --ghc-option=-predinfo=<path/to/loop_onego.bin>)



SOME MORE IMPORTANT NOTES:

The version of GHC I'm using is 8.10.3. I started with that at the beginning, and now I'm stuck with it.

The binary loop_onego.bin has the problematic inlining suggestion in it. It is included in this folder.

The binary loop_ok.bin DOES NOT have any problematic inlining suggestions in it. It's the same recommendations with "go" removed.



