#!/usr/bin/env python3
import argparse
import h5py
import numpy as np
import itertools as it
import decond.analyze as da
import matplotlib as mpl
mpl.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.ticker as ticker
from scipy import interpolate

default_outbasename = "rdf-D-decqnt"
parser = argparse.ArgumentParser(description="Plot rdf-D-decqnt")
parser.add_argument('decond', help="decond analysis file. <decond.d5>")
parser.add_argument('--decond_D', metavar='DECOND', nargs='+',
                    help="decond analysis file(s) for plotting D. <decond.d5>")
parser.add_argument('--decond_decqnt', metavar='DECOND',
                    help="decond analysis file for plotting decqnt."
                         " <decond.d5>")
parser.add_argument('--smooth_D', action='store_true',
                    help="smooth D")
parser.add_argument('-o', '--out', default=default_outbasename,
                    help="output plot file, default <{0}>".format(
                        default_outbasename))
args = parser.parse_args()

# ===================== customization =======================
# set usetex to False
# if UnicodeDecodeError occurs or the output eps is blank
usetex = True

# set which fitting results to plot
# only meaningful when multiple fit ranges are included in decond.d5
fitkey = 0

# e.g. label = ['cation', 'anion']
label = None

# the oder of color is
# [ auto-1, ..., auto-N,
#   cross-11, cross-12, cross-13, ..., cross-1N,
#             cross-22, cross-23, ..., cross-2N,
#                       ... ... ... ... ... ...
#                                      cross-NN ]
#
# e.g. color = ['b', 'g', 'b', 'r', 'g']
#
# if the provided number of colors is not enough,
# the pattern will be repeated for the rest of terms
#
# set to None for default color list (may be ugly)
# see available colors: http://matplotlib.org/api/colors_api.html
color = None

# D(r) will not be plotted if g(r) < threshold at small r region
threshold = 0  # e.g. threshold = 0.1

# the plotting range of x-axis, None for auto
xmin = None  # e.g. xmin = 0
xmax = None  # e.g. xmax = 3

rdf_top = None     # rdf_top = 2.5
D_top = None       # D_top = 0.004
D_bottom = None    # D_bottom = -0.001
sig_top = None     # sig_top = 0.75
sig_bottom = None  # sig_bottom = 0

# axis labels
# e.g.
# xlabel_rdf = r"$r$\ \ (\AA)"
# ylabel_rdf = r"$\textsl{\textrm{g}}_{IL}(r)$"
# xlabel_D = r"$r$\ \ (\AA)"
# ylabel_D = r"$D^{(1)}_I$, $D^{(2)}_{IL}(r)$\ \ (\AA$^2$ ps$^{-1}$)"
# xlabel_qnt = r"$\lambda$\ \ (\AA)"
# ylabel_qnt = r"$\sigma_I(\lambda)$\ \ (S m$^{-1}$)"
xlabel_rdf = r'$r$'
ylabel_rdf = r'$\textsl{\textrm{g}}(r)$'
xlabel_D = r'$r$'
ylabel_D = r'$D(r)$'
xlabel_qnt = r'$\lambda$'
ylabel_qnt = r'quantity$(\lambda)$'

# ticks for x-axis
xticks = None  # xticks = np.arange(0, 21, 5)
xticks_minor = None

# ticks for y-axis
rdf_yticks = None
D_yticks = None  # D_yticks = np.arange(0, 2.5, 0.5)
sig_yticks = None

rdf_legend_loc = None  # rdf_legend_loc = 'upper right'
D_legend_loc = None    # D_legend_loc = 'upper right'
sig_legend_loc = None  # sig_legend_loc = 'upper right'

# set to None to plot all components
# or set to a list to select certain indexes
# such as: rdf_plot_list = [0, 2]
# which plots the 0th and 2nd compondent of rdf
# NOTE: sdD_plot_list should be a list of list
rdf_plot_list = None
DI_plot_list = None
sdD_plot_list = None
sig_plot_list = None

xlabelpad = 1  # controls the distance between x-axis and x-axis label
ylabel_coord = (-0.18, 0.5)  # relative position of ylabel

spineLineWidth = 1.6  # line widith of bouding box
reflinewidth = 1.5  # line width of zero-reference line

figsize3 = (10, 28)  # figure size (width, height)
format = 'eps'

# relative position of (a) (b) (c) labels within each sub-figure
abc_pos = (0.03, 0.965)

# smoothing method
# http://docs.scipy.org/doc/scipy-0.15.1/reference/generated/scipy.interpolate.interp1d.html
# ‘linear’, ‘nearest’, ‘zero’, ‘slinear’, ‘quadratic, ‘cubic’
smooth = 'cubic'
num_smooth_point = 500

# set sep_nonlocal = False to turn off the local-nonlocal separation of sig_I
# D(\infty) = average of D(r) over nonlocal_ref - avewidth < r < nonlocal_ref + avewidth
# note that nonlocal_ref and avewidth are in the unit of nm
sep_nonlocal = True
nonlocal_ref = None  # default to cell-length / np.sqrt(3)
avewidth = 0.25

# other adjustment
rc = {'font': {'size': 36,
               'family': 'serif',
               'serif': 'Times'},
      'text': {'usetex': usetex},
      'legend': {'fontsize': 34},
      'axes': {'labelsize': 36},
      'xtick': {'labelsize': 36,
                'major.pad': 10,
                'major.size': 8,
                'major.width': 1.5,
                'minor.size': 4,
                'minor.width': 1.5},
      'ytick': {'labelsize': 36,
                'major.pad': 10,
                'major.size': 8,
                'major.width': 1.5,
                'minor.size': 4,
                'minor.width': 1.5},
      'lines': {'linewidth': 3},
      'savefig': {'transparent': True}}
# ===========================================================

for key in rc:
    mpl.rc(key, **rc[key])

with h5py.File(args.decond, 'r') as f:
    numMol = f['numMol'][...]
    numIonTypes = numMol.size

numIonTypePairs = numIonTypes * (numIonTypes+1) // 2

if color is None:
    color = ['b', 'g', 'r', 'c', 'm', 'y', 'k']

while len(color) < numIonTypes + numIonTypePairs:
    color += color

assert(len(color) >= numIonTypes + numIonTypePairs)

if label is None:
    label = ['{}'.format(i+1) for i in range(numIonTypes)]

assert(len(label) == numIonTypes)

label += ['-'.join(l) for l in it.combinations_with_replacement(label, 2)]

lineStyle = ['--'] * numIonTypes + ['-'] * numIonTypePairs

if (args.decond_D is None):
    decond_D = [args.decond]
else:
    decond_D = args.decond_D
    if len(decond_D) > 1:
        assert(sdD_plot_list is not None)
        assert(len(sdD_plot_list) == len(decond_D))

if (args.decond_decqnt is None):
    decond_decqnt = args.decond
else:
    decond_decqnt = args.decond_decqnt

g, rBins, rBins_unit = da.get_rdf(args.decond)[0:3]
DI, _, DI_unit, fit = da.get_D(decond_D[0])[0:4]
sdD_list = []
rBins_sdD_list = []
g_sdD_list = []

for file in decond_D:
    _sdD, _, _, _rBins_sdD = da.get_decD(file, da.DecType.spatial)[0:4]
    sdD_list.append(_sdD)
    rBins_sdD_list.append(_rBins_sdD)
    g_sdD_list.append(da.get_rdf(file)[0])

sigI, sig_unit, rBins_sigI, _, _, _, sig_local, sig_nonlocal = (
        da.get_decqnt_sd(decond_decqnt, sep_nonlocal=sep_nonlocal,
                         nonlocal_ref=nonlocal_ref, avewidth=avewidth))

print()
print("({})".format(sig_unit))
print("=======================================")
print("{:<10} {:<}".format('local', str(sig_local[fitkey])))
print("{:<10} {:<}".format('nonlocal', str(sig_nonlocal[fitkey])))
print()

if rBins_unit == da.Unit.si_length:
    rBins /= da.const.angstrom
    for rBins_sdD in rBins_sdD_list:
        rBins_sdD /= da.const.angstrom
    rBins_sigI /= da.const.angstrom

if DI_unit == da.Unit.si_D:
    DI /= da.const.angstrom**2 / da.const.pico
    for sdD in sdD_list:
        sdD /= da.const.angstrom**2 / da.const.pico

numPlots = 3

halfCellIndex = rBins.size / np.sqrt(3)
halfCellLength = rBins[halfCellIndex]

fig, axs = plt.subplots(numPlots, 1, sharex=False, figsize=figsize3)

# plot rdf
if rdf_plot_list is None:
    rdf_plot_list = list(range(numIonTypePairs))

axs[0].axhline(1, linestyle=':', color='black', linewidth=reflinewidth)

for i, rdf in enumerate(g):
    if i in rdf_plot_list:
        axs[0].plot(rBins, rdf, label=label[numIonTypes + i],
                    color=color[numIonTypes + i])

axs[0].legend(loc=rdf_legend_loc)
#    axs[0].set_title("Fit {} ps".format(fitkey))
axs[0].set_xlabel(xlabel_rdf)
axs[0].set_ylabel(ylabel_rdf)
plt.text(abc_pos[0], abc_pos[1], '(a)', transform=axs[0].transAxes,
         horizontalalignment='left', verticalalignment='top')

# plot D
axs[1].axhline(0, linestyle=':', color='black', linewidth=reflinewidth)

if DI_plot_list is None:
    DI_plot_list = list(range(numIonTypes))

for i, D in enumerate(DI[fitkey]):
    if i in DI_plot_list:
        axs[1].plot(rBins, np.ones_like(rBins)*D, label=label[i],
                    linestyle=lineStyle[i], color=color[i])

if sdD_plot_list is None:
    sdD_plot_list = [list(range(numIonTypePairs))]

for n, (sdD, rBins_sdD, g_sdD) in enumerate(
        zip(sdD_list, rBins_sdD_list, g_sdD_list)):
    for i, D in enumerate(sdD[fitkey]):
        if i in sdD_plot_list[n]:
            g_masked = np.where(np.isnan(g_sdD[i]), -1, g_sdD[i])
            idx_threshold = next(
                    i for i, g in enumerate(g_masked) if g >= threshold)

            _rBins_sdD = rBins_sdD[idx_threshold:]
            D = D[idx_threshold:]

            not_nan_D = np.logical_not(np.isnan(D))
            _rBins_sdD = _rBins_sdD[not_nan_D]
            D = D[not_nan_D]

            if args.smooth_D:
                D_interp = interpolate.interp1d(_rBins_sdD, D, kind=smooth)
                _rBins_sdD = np.linspace(
                        _rBins_sdD[0], _rBins_sdD[-1], num_smooth_point)
                D = D_interp(_rBins_sdD)

            axs[1].plot(_rBins_sdD, D, label=label[numIonTypes + i],
                        linestyle=lineStyle[numIonTypes + i],
                        color=color[numIonTypes + i])

axs[1].set_xlabel(xlabel_D)
axs[1].set_ylabel(ylabel_D)
axs[1].legend(loc=D_legend_loc)
# axs[1].legend(loc=(0.515, 0.245), labelspacing=0.2)
# axs[1].set_title("threshold {}".format(threshold))
plt.text(abc_pos[0], abc_pos[1], '(b)', transform=axs[1].transAxes,
         horizontalalignment='left', verticalalignment='top')

# plot sig
if sig_plot_list is None:
    sig_plot_list = list(range(numIonTypes))

for i, sig in enumerate(sigI[fitkey]):
    if i in sig_plot_list:
        axs[2].plot(rBins_sigI, sig, label=label[i], color=color[i])
        axs[2].legend(loc=sig_legend_loc)
axs[2].set_xlabel(xlabel_qnt)
axs[2].set_ylabel(ylabel_qnt)
plt.text(abc_pos[0], abc_pos[1], '(c)', transform=axs[2].transAxes,
         horizontalalignment='left', verticalalignment='top')

axs[0].set_ylim(top=rdf_top)
if rdf_yticks is not None:
    axs[0].set_yticks(rdf_yticks)

axs[1].set_ylim(bottom=D_bottom, top=D_top)
if D_yticks is not None:
    axs[1].set_yticks(D_yticks)

axs[2].set_ylim(bottom=sig_bottom, top=sig_top)
if sig_yticks is not None:
    axs[2].set_yticks(sig_yticks)

if xmax is None:
    xmax = halfCellLength
for ax in axs:
    if xticks is not None:
        ax.set_xticks(xticks)
    ax.set_xlim(left=xmin, right=xmax)
    if xticks_minor is not None:
        ax.xaxis.set_minor_locator(ticker.AutoMinorLocator(xticks_minor))
    ax.xaxis.labelpad = xlabelpad
    ax.yaxis.set_label_coords(ylabel_coord[0], ylabel_coord[1])
    for sp in ax.spines.values():
        sp.set_linewidth(spineLineWidth)

# plt.tight_layout()
# plt.subplots_adjust(left=None, bottom=None, right=None, top=None,
# wspace=None, hspace=None)
plt.subplots_adjust(hspace=0.25)
plt.savefig(args.out + '.' + format, bbox_inches="tight")
