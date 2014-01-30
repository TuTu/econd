#!/home/kmtu/bin/octave -qf

% ***** NOTE *****
% This version2 calculates the md statistics by
% loading the md data files one by one.
% The efficiency is sacrificed to save memory.
% So if the numMD is not large, say, only 10,
% please use the version1, instead.

clear all;
global numIonTypes constant;
constant.kB = 1.3806488E-23; #(J K-1)
constant.beta = 1.0/(constant.kB*300); #(J-1)
constant.basicCharge = 1.60217646E-19; #(Coulomb)
constant.ps = 1.0E-12; #(s)
constant.nm = 1.0E-9; #(m)

if (nargin() < 4)
    error("Usage: $fitAveNoAverageCesaro-sdD.m <dataFilename> <numMD> <skip> <dt> [num_rBins]")
endif

dataFilename = argv(){1}
numMD = str2num(argv(){2})
if (numMD < 2)
    error(cstrcat("Error: numMD < 2. This version2 only accepts multiple MD files.\n",\
                  "       For single MD file, use version1, instead."))
endif

skip = str2num(argv(){3}) #skipped interval in sdCorr data
deltaStep = str2num(argv(){4})

if (nargin() > 4)
  num_rBins = str2num(argv(){5});
endif

set(0, "defaultlinelinewidth", 4);

function index = zipIndexPair(idx1, idx2)
    global numIonTypes;
    index = (idx1 - 1) * numIonTypes + idx2;
endfunction

for n = [1:numMD]
  dataPath{n} = strcat("./md", num2str(n-1), "/", dataFilename);
endfor

if (exist("num_rBins", "var") != 1)
  puts("Loading data files to determine rBins\n");
  for n = [1:numMD]
      puts(cstrcat("Loading MD data #", num2str(n), "...\n"));
      if (n == numMD)
        load(dataPath{n}, "charge", "numIonTypes", "timestep", "timeLags", "rBins", "numAtom");
      else
        load(dataPath{n}, "rBins");
      endif
      num_rBins_tmp(n) = length(rBins);
  endfor
  num_rBins = min(num_rBins_tmp)
  clear("num_rBins_tmp");
else
  puts(cstrcat("num_rBins is given: ", num2str(num_rBins), "\n")); 
  puts(cstrcat("Loading the 1st MD data to determine basic information...\n"));
  puts(cstrcat("Loading MD data #", num2str(1), "...\n"));
  load(dataPath{1}, "charge", "numIonTypes", "timestep", "timeLags", "rBins", "numAtom");
endif 
rBins = rBins(1:num_rBins);

numIonTypePairs = (numIonTypes*(numIonTypes+1))/2; 

# md(sdCorr_timeLag, sdCorr_rBin, sdCorrIonTypePairIndex, fileIndex)
# calculate md.sum to get md.ave
puts("Loading data files to determine md.sum\n");
md.sum = zeros(length(timeLags), num_rBins, numIonTypePairs);
volume.sum = 0;
rho2.sum = 0;
for n = [1:numMD]
    puts(cstrcat("md.sum: n=", num2str(n), "\n"));
    tmpData = load(dataPath{n}, "cell", "rho2", "sdD_noAveCesaro");
    volume.sum += prod(tmpData.cell);
    rho2.sum += tmpData.rho2(1:num_rBins, :); 
    md.sum .+= tmpData.sdD_noAveCesaro(:, 1:num_rBins, :);
endfor
clear("tmpData");

volume.ave = volume.sum ./ numMD;
rho2.ave = rho2.sum ./ numMD;
md.ave = md.sum ./ numMD;
clear("md.sum");
clear("rho2.sum");
clear("volume.sum");

# calculate std
puts("Loading data files to determine ave and std\n");
volume.std = 0;
md.std = zeros(length(timeLags), num_rBins, numIonTypePairs);
rho2.std = zeros(num_rBins, numIonTypePairs); 
for n = [1:numMD]
    puts(cstrcat("md.std: n=", num2str(n), "\n"));
    tmpData = load(dataPath{n}, "cell", "rho2", "sdD_noAveCesaro");
    volume.std .+= (prod(tmpData.cell) - volume.ave).^2;
    rho2.std .+= (tmpData.rho2(1:num_rBins, :) .- rho2.ave).^2;
    md.std .+= (tmpData.sdD_noAveCesaro(:, 1:num_rBins, :) .- md.ave).^2;
endfor
volume.std = sqrt(volume.std ./ (numMD - 1));
rho2.std = sqrt(rho2.std ./ (numMD - 1));
md.std = sqrt(md.std ./ (numMD - 1));
volume.err = volume.std ./ sqrt(numMD); # standard error
rho2.err = rho2.std ./ sqrt(numMD); # standard error
md.err = md.std ./ sqrt(numMD); # standard error


%********** Fitting **********
fitRange = [20, 40; 40, 60; 60, 80; 80, 100]; #ps
%fitRange = [2, 4; 4, 6; 6, 8; 8, 10]; #ps
fitRange *= floor(1000 / skip / deltaStep); #fs (frame)

# calculate slope for each segment of md.ave
for i = [1:numIonTypePairs]
  for j = [1:num_rBins]
    for r = [1:size(fitRange, 1)]
        slope(r,j,i) = polyfit(timeLags(fitRange(r, 1):fitRange(r, 2)), md.ave(fitRange(r, 1):fitRange(r, 2), j, i), 1)(1);
    endfor
  endfor
endfor

# evaluate the uncertainty in the slope of the fitting line
# reference: Numerical Recipes Chapter 15.2 (p.656)
for i = [1:numIonTypePairs] 
  for j = [1:num_rBins]
    for r = [1:size(fitRange, 1)]
        rec_sig2 = 1 ./ (md.std(fitRange(r, 1):fitRange(r, 2), j, i) .^ 2);
        S(r, j, i) = sum(rec_sig2, 1);
        Sx(r, j, i) = sum(timeLags(fitRange(r, 1):fitRange(r, 2)) .* rec_sig2, 1); 
        Sxx(r, j, i) = sum(timeLags(fitRange(r, 1):fitRange(r, 2)).^2 .* rec_sig2, 1); 
        Sy(r, j, i) = sum(md.ave(fitRange(r, 1):fitRange(r, 2), j, i) .* rec_sig2, 1);
        Syy(r, j, i) = sum(md.ave(fitRange(r, 1):fitRange(r, 2), j, i).^2 .* rec_sig2, 1);
        Sxy(r, j, i) = sum(timeLags(fitRange(r, 1):fitRange(r, 2)) .* md.ave(fitRange(r, 1):fitRange(r, 2), j, i) .* rec_sig2, 1); 
    endfor
  endfor
endfor
Delta = S .* Sxx - Sx .* Sx;

# output slope for double check
slope_b = (S .* Sxy - Sx .* Sy) ./ Delta;
slopeSD = sqrt(S ./ Delta);

save(strcat(dataFilename, '-ave', num2str(numMD), '.fit'), "constant", "charge",\
     "numIonTypes", "numAtom", "timestep", "timeLags", "rBins", \
     "volume", "rho2", "md", "slope", "slopeSD");

%save(strcat('ecNoAverageCesaro-skip-', num2str(skip), '-dt-', num2str(deltaStep), '.fit'), "numIonTypes", "timeLags", "md_ave", "md_std", "md_err", "slope", "slopeSD");

%#numPlots = 1 + numIonTypes + numIonTypes*numIonTypes;
%
%# standard error for selected values
%errFrameInterval = floor(5000 / skip / deltaStep);
%errFrames = [1:errFrameInterval:length(timeLags)]';
%
%
%f1 = figure(1);
%clf;
%hold on;
%errOffset = floor(200 / skip / deltaStep);
%
%for i = [1:numIonTypePairs]
%    drawFrames = errFrames .+ (i-1)*errOffset;
%    drawFrames = drawFrames(drawFrames <= length(timeLags));
%    if (i == 6)
%#        p(i).plot = plot(timeLags, md_ave(:,i), "-", "color", [0, 0.6, 0]);
%        p(i).errorbar = errorbar(timeLags(drawFrames), md_ave(drawFrames,i), md_err(drawFrames,i));
%        set(p(i).errorbar(1), "color", [0, 0.6, 0]);
%    elseif (i == 7)
%#        p(i).plot = plot(timeLags, md_ave(:,i), "-", "color", [0, 0, 0]);
%        p(i).errorbar = errorbar(timeLags(drawFrames), md_ave(drawFrames,i), md_err(drawFrames,i));
%        set(p(i).errorbar(1), "color", [0, 0, 0]);
%    else
%        plotFormat = strcat("-", num2str(i));
%        errorbarFormat = strcat("~", num2str(i));
%        p(i).errorbar = errorbar(timeLags(drawFrames), md_ave(drawFrames,i), md_err(drawFrames,i), errorbarFormat);
%#        p(i).plot = plot(timeLags, md_ave(:,i), plotFormat);
%    endif
%endfor
%
%legend("Total", "Na-Na", "Na-Cl", "Cl-Na", "Cl-Cl", "location", "northwest");
%
%left = 25;
%h_space = 20;
%top = 972;
%v_space = 44;
%for i = [1:size(md_ave, 2)]
%    for r = [1:size(fitRange, 1)]
%        text(left + (r-1)*h_space, top - (i-1)*v_space, num2str(slope(r, i)));
%    endfor
%endfor
%
%title(cstrcat("Non-averaged Cesaro sum for electrical conductivity of 1m NaCl solution\n",\
%             "data interval = ", num2str(skip), ", integration interval = ", num2str(deltaStep)));
%xlabel("partial sum upper limit (ps)");
%ylabel("Non-averaged partial sum (ps*S/m)");
%axis([0,100,-600, 1000]);
%
%print(strcat('ecNoAverageCesaro-', 'ave-skip-', num2str(skip), '-dt-', num2str(deltaStep), '.eps'), '-deps', '-color');
%hold off
%
%##############################
%
%# standard deviation for selected values
%for i = [1:size(fitRange, 1)]
%    stdFrames(i) = (fitRange(i, 1) + fitRange(i, 2)) / 2;
%endfor
%
%f2 = figure(2);
%%clf;
%hold on;
%stdOffset = floor(100 / skip / deltaStep);
%
%for i = [1:numIonTypePairs]
%    drawFrames = stdFrames .+ (i-1)*stdOffset;
%    if (i == 6)
%        p(i).errorbar = errorbar(timeLags(drawFrames), slope(:,i), slopeSD(:,i));
%        set(p(i).errorbar(1), "color", [0, 0.6, 0]);
%    elseif (i == 7)
%        p(i).errorbar = errorbar(timeLags(drawFrames), slope(:,i), slopeSD(:,i));
%        set(p(i).errorbar(1), "color", [0, 0, 0]);
%    else
%        plotFormat = strcat("-", num2str(i));
%        errorbarFormat = strcat("~", num2str(i));
%        p(i).errorbar = errorbar(timeLags(drawFrames), slope(:,i), slopeSD(:,i), errorbarFormat);
%    endif
%endfor
%
%legend("Total", "Auto Na+", "Auto Cl-", "Cross Na-Na", "Cross Na-Cl", "Cross Cl-Na", "Cross Cl-Cl", "location", "northwest");
%
%title(cstrcat("Non-averaged Cesaro sum for electrical conductivity of 1m NaCl solution\n",\
%             "data interval = ", num2str(skip), ", integration interval = ", num2str(deltaStep)));
%xlabel("partial sum upper limit (ps)");
%ylabel("Electrical conductivity (S/m)");
%axis([0,100,-5, 10]);
%
%print(strcat('ecNoAverageCesaro-', 'ave-slope-skip-', num2str(skip), '-dt-', num2str(deltaStep), '.eps'), '-deps', '-color');
