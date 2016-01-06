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

default_outbasename = "g-D-ecdec"
parser = argparse.ArgumentParser(description="Plot rdf-D-ecdec")
parser.add_argument('decond', help="decond analysis file. <decond.d5>")
parser.add_argument('--decond_D', metavar='DECOND',
                    help="decond analysis file for plotting D. <decond.d5>")
parser.add_argument('--decond_ecdec', metavar='DECOND',
                    help="decond analysis file for plotting ecdec. <decond.d5>")
parser.add_argument('-o', '--out', default=default_outbasename,
                    help="output plot file, default <{0}>".format(
                        default_outbasename))
parser.add_argument('-c', '--custom', action='store_true',
                    help="Read the customized parameters in the script")
args = parser.parse_args()

# ======= basic customization ==========
if args.custom:
    label = ['cation', 'anion']
    color = ['b', 'g', 'b', 'r', 'g']
    threshold = 0.1

    rdf_top = 2.5
    D_top = 0.004
    D_bottom = -0.001
    sig_top = 0.75
    sig_bottom = 0

    # set to None for auto-ranges
    xmin = None
    xmax = None

    # set to None for auto-ticks
    xticks = np.arange(0, 21, 5)

    rdf_legend_loc = 'upper right'
    D_legend_loc = 'upper right'
    sig_legend_loc = 'upper right'

    # set to None to plot all components
    # or set to a list to select certain indexes
    # such as:
    # rdf_plot_list = [0, 2]
    # which plots the 0th and 2nd compondent of rdf
    rdf_plot_list = None
    DI_plot_list = None
    sdD_plot_list = None
    sig_plot_list = None
# ======================================
else:
    threshold = 0
    color = ['b', 'r', 'g', 'c', 'm', 'y', 'k']
    rdf_legend_loc = 'upper right'
    D_legend_loc = 'upper right'
    sig_legend_loc = 'upper right'
    rdf_plot_list = None
    DI_plot_list = None
    sdD_plot_list = None
    sig_plot_list = None

rc = {'font': {'size': 36,
               'family': 'serif',
               'serif': 'Times'},
      'text': {'usetex': True},
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
      'lines': {'linewidth': 3}}

for key in rc:
    mpl.rc(key, **rc[key])

labelpad = 10
spineLineWidth = 1.6
reflinewidth = 1.5

figsize3 = (10, 28)
format = 'eps'

with h5py.File(args.decond, 'r') as f:
    numMol = f['numMol'][...]
    numIonTypes = numMol.size

numIonTypePairs = numIonTypes * (numIonTypes+1) // 2

if (not args.custom):
    label = ['{}'.format(i+1) for i in range(numIonTypes)]
lineStyle = ['--'] * numIonTypes + ['-'] * numIonTypePairs
label += ['-'.join(l) for l in it.combinations_with_replacement(label, 2)]

fitKey = 0

if (args.decond_D is None):
    decond_D = args.decond
else:
    decond_D = args.decond_D

if (args.decond_ecdec is None):
    decond_ecdec = args.decond
else:
    decond_ecdec = args.decond_ecdec

g, rBins = da.get_rdf(args.decond)[0:2]
DI, _, _, fit = da.get_diffusion(decond_D)[0:4]
sdD, _, _, rBins_sdD = da.get_decD(decond_D, da.DecType.spatial)[0:4]
g_sdD = da.get_rdf(decond_D)[0]
sigI, _, rBins_sigI = da.get_ec_dec(decond_ecdec, da.DecType.spatial)[0:3]

rBins /= da.const.angstrom
rBins_sdD /= da.const.angstrom
rBins_sigI /= da.const.angstrom
DI /= da.const.angstrom**2 / da.const.pico
sdD /= da.const.angstrom**2 / da.const.pico

numPlots = 3

halfCellIndex = rBins.size / np.sqrt(3)
halfCellLength = rBins[halfCellIndex]

smallRegion = []
for rdf in g_sdD:
    smallRegion.append(next(i for i, v in enumerate(rdf) if v >= 1))

fig, axs = plt.subplots(numPlots, 1, sharex=False, figsize=figsize3)

abcPos = (0.03, 0.965)

# plot rdf
if args.custom:
    axs[0].set_color_cycle(color[numIonTypes:])

if rdf_plot_list is None:
    rdf_plot_list = list(range(numIonTypePairs))

axs[0].axhline(1, linestyle=':', color='black', linewidth=reflinewidth)

for i, rdf in enumerate(g):
    if i in rdf_plot_list:
        axs[0].plot(rBins, rdf, label=label[numIonTypes + i],
                    color=color[numIonTypes + i])

axs[0].legend(loc=rdf_legend_loc)
#    axs[0].set_title("Fit {} ps".format(fitKey))
axs[0].set_xlabel(r"$r$\ \ (\AA)", labelpad=labelpad)
axs[0].set_ylabel(r"$\textsl{\textrm{g}}_{IL}(r)$", labelpad=labelpad)
plt.text(abcPos[0], abcPos[1], '(a)', transform=axs[0].transAxes,
         horizontalalignment='left', verticalalignment='top')

# plot D
axs[1].axhline(0, linestyle=':', color='black', linewidth=reflinewidth)

if DI_plot_list is None:
    DI_plot_list = list(range(numIonTypes))

for i, D in enumerate(DI[fitKey]):
    if i in DI_plot_list:
        axs[1].plot(rBins, np.ones_like(rBins)*D, label=label[i],
                    linestyle=lineStyle[i], color=color[i])

if sdD_plot_list is None:
    sdD_plot_list = list(range(numIonTypePairs))

for i, D in enumerate(sdD[fitKey]):
    if i in sdD_plot_list:
        g_masked = np.where(np.isnan(g_sdD[i]), -1, g_sdD[i])
        D_masked = np.ma.masked_where(
                [c if j <= smallRegion[i] else False
                 for j, c in enumerate(g_masked < threshold)], D)
        axs[1].plot(rBins_sdD, D_masked, label=label[numIonTypes + i],
                    linestyle=lineStyle[numIonTypes + i],
                    color=color[numIonTypes + i])

axs[1].set_xlabel(r"$r$\ \ (\AA)", labelpad=labelpad)
axs[1].set_ylabel(r"$D^{(1)}_I$, $D^{(2)}_{IL}(r)$\ \ (\AA$^2$ ps$^{-1}$)",
                  labelpad=labelpad)
axs[1].legend(loc=D_legend_loc)
# axs[1].legend(loc=(0.515, 0.245), labelspacing=0.2)
# axs[1].set_title("threshold {}".format(threshold))
plt.text(abcPos[0], abcPos[1], '(b)', transform=axs[1].transAxes,
         horizontalalignment='left', verticalalignment='top')

# plot sig
if sig_plot_list is None:
    sig_plot_list = list(range(numIonTypes))

for i, sig in enumerate(sigI[fitKey]):
    if i in sig_plot_list:
        axs[2].plot(rBins_sigI, sig, label=label[i], color=color[i])
        axs[2].legend(loc=sig_legend_loc)
axs[2].set_xlabel(r"$\lambda$\ \ (\AA)", labelpad=labelpad)
axs[2].set_ylabel(r"$\sigma_I(\lambda)$\ \ (S m$^{-1}$)", labelpad=labelpad)
plt.text(abcPos[0], abcPos[1], '(c)', transform=axs[2].transAxes,
         horizontalalignment='left', verticalalignment='top')

if args.custom:
    axs[0].set_ylim(top=rdf_top)
    axs[1].set_ylim(bottom=D_bottom, top=D_top)
    # axs[1].set_yticks(np.arange(0, 2.5, 0.5))
    axs[2].set_ylim(bottom=sig_bottom, top=sig_top)

for ax in axs:
    if args.custom:
        if xticks is not None:
            ax.set_xticks(xticks)
        if xmax is None:
            xmax = halfCellLength
        ax.set_xlim(left=xmin, right=xmax)
    else:
        ax.set_xlim(right=halfCellLength)
    ax.xaxis.set_minor_locator(ticker.AutoMinorLocator(5))
    ax.xaxis.labelpad = 1
    ax.yaxis.set_label_coords(-0.18, 0.5)
    for sp in ax.spines.values():
        sp.set_linewidth(spineLineWidth)

# plt.tight_layout()
# plt.subplots_adjust(left=None, bottom=None, right=None, top=None,
# wspace=None, hspace=None)
plt.subplots_adjust(hspace=0.25)
plt.savefig(args.out + '.' + format, bbox_inches="tight")
