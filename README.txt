README

Ex-Vivo Analysis Workflow Application
version 1.0
Date: July 17, 2026
Author: Gerry Herrera, The University of Vermont
email: gmherrer@uvm.edu

Version History:
1.0 - July 17, 2026 - Initial Release


This application is a package of Matlab functions and scripts intended for use in analyzing physiological data obtained from the "Ex-Vivo Bladder Preparation."  Features include: categorizing data into experimental groups, extracting pressure/volume, pressure/afferent nerve, volume/afferent-nerve, pressure/afferent-nerve relationships, analyzing transient pressure events, and creating plots of raw and processed data.

Requirements:	MATLAB 2024a or newer
		Signal Processing Toolbox

Input Data
  The workflow is designed for Spike2 "Spreadsheet Text" exports generated from Cambridge Electronic Design (CED) Spike2.

Output
  The import workflow produces a curated MATLAB (*.mat) data structure that serves as the canonical dataset for all downstream analyses.


Main Workflow:
	ImportAndCurate_Spike2Data
   		 → canonical curated MAT dataset; use this to start a data set or add files to existing data set

	binningAnalysisGUI
    		→ grouped 2D binning; use this to analyze and plot pressure/volume, pressure/nerve, volume/nerve 		relationships.

	TPEanalysisGUI
    		→ TPE detection and QC; use this to analyze transient pressure events

Installation:
1. Download or clone this repository.
2. Place all source files in a single folder.
3. Add the folder to the MATLAB path.
4. Launch MATLAB.
5. Run:     ImportAndCurate_Spike2Data


The compilation contains the following source files (in alphabetical order):
  assignExperimentalGroupsUI.m - Version 1.0
	UI to map detected condition keys -> user-defined group labels.
  baseline.m - Version 1.0
	Data processing algorithm that performs baseline correction using asymmetric least squares smoothing.
  bin2DByGroup.m - Version 1.0
	General grouped 2D binning for paired X/Y data vectors.
  bin2DByGroup_equalN.m - Version 1.0
	General grouped 2D trajectory binning for paired X/Y data vectors. Each replicate is divided into N     	sequential bins with approximately equal number of data points per bin, rather than fixed width bins.
  binningAnalysisGUI.m - Version 1.0
	GUI Wrapper for grouped 2D binning functions.
  detectTPEs.m - Version 1.0
	Detect transient pressure events (TPEs) using findpeaks on baseline-subtracted pressure.
  getConditionDictionary.m - Version 1.0
	Returns condition dictionary (defaults + user customizations). Used for categorizing experiments into 	groups.
  ImportAndCurate_Spike2Data.m - Version 1.1
	Script that launches data analysis workflow. Used to build or append to the canonical afferent nerve data 	structure from Spike2 Spreadsheet Text exports.
  inspectSpike2Txt.m
	Read-only inspector for Spike2 "Spreadsheet Text" exports.
  loadSpike2Batch.m - Version 1.0
	Loads Spike2 Spreadsheet Text files, select channels, compute volume, and extracts filename metadata (ALL 	underscore tags) + parsed indicators (FillN, conditions, sec-sec window).
  plotBinned2DByGroup.m - Version 1.0
	Plots grouped 2D binned data with both X and Y error bars.
  plotRawPrepOverlaySparklines.m - Version 1.0
	Plots raw-data sparklines with treatment groups overlaid for each preparation.
  processSpike2Batch.m - Version 1.0
	Performs smoothing + baseline/peak-envelope fits for pressure and nerve Hz, and compute max volume + 	optional volume normalization (% of max).
  TPEanalysisGUI.m - Version 1.0
	GUI wrapper for transient pressure event (TPE) analysis.
	
  

  
	

  
	

 
