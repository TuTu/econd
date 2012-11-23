#!/home/kmtu/bin/octave -qf

clear all
format long

if (nargin() < 2)
    error("Usage: $convertVelData.m <data.trr> <outFileName>")
endif

dataFileName = argv(){1}
outFileName = argv(){2}

trr2matlab(dataFileName, 'v', outFileName)

