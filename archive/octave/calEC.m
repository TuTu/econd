#!/home/kmtu/bin/octave -qf

clear all
format long

global kB beta basicCharge ps nm volume timestep t maxLag;

kB = 1.3806488E-23; #(J K-1)
beta = 1.0/(kB*300); #(J-1)
basicCharge = 1.60217646E-19; #(Coulomb)
ps = 1.0E-12; #(s)
nm = 1.0E-9; #(m)


if (nargin() < 3)
    error("Usage: $calEC.m <filename.vCorr> <maxLag -1=max> <systemVolume(nm^3)>\n\
where <filename> is used for both input and output: filename.vCorr and filename.ec");
else
    filename = argv(){1};
    extnamePos = rindex(filename, "."); #locate the position of the extension name
    baseFilename = filename(1:extnamePos-1);
    maxLag = str2num(argv(){2});
    volume = str2num(argv(){3}) * (1.0E-9)**3; #(m3)
endif

#.vCorr file contains timestep, charge(), numAtoms(), timeLags(), vAutocorr{}, and vCorr{}
load(filename);

numIonTypes = length(vAutocorr);
if (numIonTypes != length(vCorr))
    error(strcat("Numbers of ion types are inconsistent!\n\
vAutocorr: ", num2str(length(vAutocorr)), ", vCorr: ", num2str(length(vCorr))));
endif

if (maxLag < 0)
    maxLag = length(vAutocorr{1}) - 1;
endif
maxLag #for showing

t = [0:maxLag];

function ec = integrateEC(corrData)
    global kB beta basicCharge ps nm volume timestep t maxLag;
    if (length(corrData) == 1 && maxLag > 0)
        #there is only one ion so no mutual-corr{i}{i}
        ec = 0;
    else
        ec = beta * basicCharge**2 / volume * trapz(t', corrData(1:maxLag+1)) * timestep * nm**2 / ps;
    endif
endfunction

ecTotal = 0;
for i = [1:numIonTypes]
    ecAutocorr(i) = charge(i) * charge(i) * integrateEC(vAutocorr{i});
    ecTotal = ecTotal + ecAutocorr(i);
    for j = [1:numIonTypes]
        ecCorr(i,j) = charge(i) * charge(j) * integrateEC(vCorr{i,j});
        ecTotal = ecTotal + ecCorr(i,j);
    endfor
endfor

ecCorr
ecAutocorr
ecTotal
save(strcat(baseFilename, ".ec"), "ecTotal", "ecAutocorr", "ecCorr");
