%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%                            PRESTUS WRAPPER                              %
%                                                                         %
% Author: Marwan Engels                                                   %
% Originally made for project: Neuromodulation of Control Beliefs.        %
%                                                                         %
% This script is used to perform PRESTUS simulations.                     %
%                                                                         %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%                                                                         %
%                                NOTES                                    %
%                                                                         %
% Author: Marwan Engels
% Date: 30/06/2026
% Labs: Motivational & Cognitive Control lab & Cognitive Neuromodulation Lab
%       Donders Institute, Nijmegen.
%
% This script runs the Neuromodulation of Control Beliefs TUS protocol.
% Simultaneously delivers a TUS protocol, plays an auditory masking souhnd, and records Localite Instrument markers. 
% - Can run both a full TUS protocol and a pilot version (i.e., 5 seconds stimulation) 
%
% NOTE: DEVELOPMENT STATUS: This script is currently under active development and is provided AS IS. 
% Script may be incomplete, undergo significant changes, or contain bugs. Use at your own discretion.
%
% Matlab 2023B                                                            
% PRESTUS Git version: @ e6bd1b2                                          
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% Fresh start
clear, close all
clc

% ======================================================================= %
% GENERAL SETTINGS FOR RUNNING A SIMULATION
% Run
run_sims = 0;               % 1 to run simulations / 0 to only run this pipeline in matlab for bugchecks

run_heating = 1;            % 1 to run heating / 0 to not.
run_sequential = 1;         % 1 to run sequential heating simulations / 0 to only 1 single acoustic. NOTE: if 1 and run_sims = 0, nothing will be actually simulated.
run_segmentation_only = 0;  % 1 to only run segmentation, 0 to allow sims to be run.
run_acoustic_sim = 1;       % 1 to run acoustic sims. set to 0 if acoustic is finished and only therman sims are needed.

save_json = 1;              % save the focal distance in json format
preview_transducer_loc = 1; % 1 to plot transducer location before starting simulation
save_big_matfiles = 1;      % Take a lot of memory. Required for thermal sims. Set to 0 if you do not want to save the big matrices in the cache and debug folders.
run_PLANTUS = 0;            % Set to 1 for using PlanTUS
uncertainty_mode = false;   % set to true to run the uncertainty mode, i.e.:3 sims: liberal, normal & conservative.

% Transducer
localite_coordinates = 1;   % 1 to use localite InstrumentMarkers & apply coupler_to_transducer_distance

% Type
sim_resolution = 'turbo';   % 'turbo' = 2mm, 'quick' = 1mm, 'detailed' = 0.5mm affix, any other gives error
medium = 'layered';         % 'water' or 'layered'
submit = 'slurm';           % run scripts via 'matlab' (debugging) or via a job using 'slurm' (recommended) or 'qsub'
debug_mode = 1;             % For now required... WORK IN PROGRESS

% ======================================================================= %
% PATHS
base_dir = '/project/3017083.05';                           % project folder
sims_d  = 'sims';                                           % relative to base_dir -> where to save the simulations
data_d = 'data';                                            % relative to base_dir -> where the localite data is stored
default_cfg_d = 'CtrlTUS_scripts/TUS_simulations/configs';  % relative to base_dir -> where the default config is stored
admin_d = 'CtrlTUS_scripts/TUS_simulations';                % relative to base_dir -> where the excel sheet with voxel coords is stored
calibration_d = 'sims/calibration/optimized';               % relative to base_dir -> where transducer calibration files are stored

% CONFIG FILE NAMES
pgACC_config_file = 'config_pgACC_20260611.yaml';
striatum_config_file = 'config_striatum_20260611.yaml';
thalamus_config_file = 'config_thalamus_20260611.yaml';
entorhinal_config_file = 'entorhinal_20260626.yaml';
excel_file = 'MarwanEngels_repeated_stimulation_config_4share.xlsx';

% TOOLBOXES & FUNCTIONS 
addpath(genpath(fullfile(base_dir, 'CtrlTUS_scripts/toolboxes/PRESTUS/external'))) % Toolboxes
addpath(genpath(fullfile(base_dir, 'CtrlTUS_scripts/toolboxes/PRESTUS/functions'))) % Functions
addpath(genpath(fullfile(base_dir, 'CtrlTUS_scripts/TUS_simulations/configs'))) % Configs

% ======================================================================= %
% Load simulation excel files
% Session
run_table = readtable(fullfile(base_dir, admin_d, excel_file), 'Sheet', 'Run_sims', 'VariableNamingRule', 'preserve'); % Select sheets Excel file.
run_table = run_table(run_table.r_submit == 1, :); % Filter rows Excel file.
repeated_stimulation_table = readtable(fullfile(base_dir, admin_d, excel_file), 'Sheet', 'Exact_sims', 'VariableNamingRule', 'preserve'); % Filter specific targets in session

% ======================================================================= %
% Localite settings for localite v4.0 TriggerMarker parsing
ISI_thresh = 7;             % [s] time between sequential sonications: used for segmenting the TriggerMarker into separate epochs per target
SI_dur = 60;                % [s] total duration of recording markers per target sonication
tracker_to_bowl_mm = -11.7; % mm between EP and concave face of transducer

% Localite settings for localite v3.49 Instrument Marker parsing
coupler_to_transducer_distance = -10; % LEGACY: Shift distance in mm between transducer bowl and coupling system holding transducer face.WORKS ONLY IF USING COORDS FROM LOCALITE

% ======================================================================= %
% SIM TYPE SETTINGS & SLURM PREP
if run_heating == 1
    timelimit = '30:00:00';
        memorylimit = 64;
    else
        timelimit = '04:00:00';
        memorylimit = 40;
end

% DEFINE GRID STEP FOR FAST COMPUTATIONS
if strcmp(sim_resolution, 'quick')
    sim_mm = 1;      % 1 mm
    time_interval = 15; % number of minutes between each interval
    sim_res_affix = '1mm';
elseif strcmp(sim_resolution, 'turbo')
    sim_mm = 2;      % 2 mm
    time_interval = 4; % number of minutes between each interval
    sim_res_affix = '2mm';
elseif strcmp(sim_resolution, 'detailed')
    sim_mm = 0.5;    % 0.5 mm 
    time_interval = 90; % number of minutes between each interval
    sim_res_affix = '05mm';
else
    error('Unknown sim_resolution option.');
end

% ======================================================================= %
% INITIALIZE

focus_results = struct([]); % json Focal depth table

% ======================================================================= %
%% Run simulations 
% Loop over specific subject-region-focus-intensity combinations (e.g., pgACC, caudate, putamen or sham)
% Note: runs for each set of targets the same intensity and foc
% depth (e.g., does not change between left pgACC and right pgACC, or anterior striatum and posterior striatum). 

for j = 1:height(run_table)
    
    % Define what to simulate.
    subject_id = run_table.r_subjects(j);
    sub_str = sprintf('sub-%03d', subject_id);
    region = run_table.r_regions{j};
    F_value = run_table.r_foc_distances(j);
    I_value = run_table.r_intensities(j);
    
    % Directories
    data_d  = sprintf('bids/sub-%03d/ses-mri01/anat', subject_id);
    default_config_dir = fullfile(base_dir, default_cfg_d); % folder where study-default config is stored
    localite_dir = fullfile(base_dir, 'data', sub_str); % where subject localite instrument files are stored
    calibration_dir = fullfile(base_dir, calibration_d); % where the calibration/transducer profiles are stored
    disp(localite_dir)
    
    % ======================================================================= %
    %% Load parameters
    % Load the Study-default Region-specific config file:
    if ismember(region, {'sham', 'pgACC', 'TEST'})
        parameters = load_parameters(sprintf('%s/%s', default_config_dir, pgACC_config_file));
    elseif startsWith(region, 'caudate')
        parameters = load_parameters(sprintf('%s/%s', default_config_dir, striatum_config_file));
    elseif strcmp(region, 'thalamus')
        parameters = load_parameters(sprintf('%s/%s', default_config_dir, thalamus_config_file));
    elseif strcmp(region, 'entorhinal')
        parameters = load_parameters(sprintf('%s/%s', default_config_dir, entorhinal_config_file));
    else
        error('Unrecognized region: "%s" \nSee Load parameters section (line ~140)', region);
    end

    parameters.subject_id = subject_id;
    
    % Simulation parameters
    parameters.platform = submit;
    parameters.simulation.medium = medium;
    parameters.modules.run_heating_sims = run_heating;
    parameters.modules.segmentation_only = run_segmentation_only;
    parameters.modules.run_acoustic_sims = run_acoustic_sim;
    parameters.simulation.uncertainty = uncertainty_mode;
    parameters.simulation.debug = debug_mode;

    % Paths
    parameters.path.anat = fullfile(base_dir, data_d);
    parameters.path.sim = fullfile(base_dir, sims_d);
    parameters.path.seg = fullfile(base_dir, sims_d, sub_str);
    parameters.path.localite = fullfile(localite_dir, region);
    parameters.path.t1_pattern = sprintf('sub-%03d_ses-mri01_acq-mprage_T1w.nii.gz', subject_id); % T1 nifti file (e.g., sub-701_ses-mri01_acq-mprage_T1w.nii)
    parameters.path.t2_pattern = sprintf('sub-%03d_ses-mri01_acq-t2space_echo-1_T2w.nii.gz', subject_id); % T2 nifti file 
    parameters.io.dir_output = fullfile(base_dir, sims_d, sub_str, 'nii');
    parameters.io.dir_reports = fullfile(base_dir, sims_d, sub_str, 'reports');
    parameters.io.dir_tabular = fullfile(base_dir, sims_d, sub_str, 'reports');

    % Other settings
    parameters.io.savematrices = save_big_matfiles;
    parameters.hpc.timelimit = timelimit;
    parameters.hpc.memorylimit = memorylimit;
    parameters.grid.resolution_mm = sim_mm; 
    
    % INITIALIZE/RESET FOR HEATING SIMS
    consecutive_simulation_number = 1; % Should start at 1!
    sequential_configs = struct();
    options = struct();
    
    % Define sim type for affix
    if localite_coordinates == 1
        simtype_aff = 'posthoc'; % Localite TriggerMarkers
    elseif localite_coordinates == 0
        simtype_aff = 'apriori'; % Excel sheet
    else
        simtype_aff = 'legacy'; % Localite Instrument Marker
    end

    % ======================================================================= %
    %% Index specific simulations from Excel file.
    % From excel sheet, grab the to-be stimulated targets of that subject
    subject_and_target_index = repeated_stimulation_table.subject_id == subject_id...
        & strcmp(repeated_stimulation_table.region, region);
    filtered_table = repeated_stimulation_table(subject_and_target_index, :);

    % Save for later
    base_file_affix = parameters.io.output_affix; % Save for re-use when sequentially simulating.
    hemispheres = filtered_table.hemisphere;
    target_numbers = filtered_table.target_nr;
    exact_targets = filtered_table.stimulation_target;
    trans_models = filtered_table.transducer_model;
    stim_orders = filtered_table.stim_order;
    
    fprintf('Running subject: %d [%s], F=%d, I=%d \n', subject_id, region, F_value, I_value);
    
   
    % ======================================================================= %
    %% LOAD T1 INFO
    % Load structural data for 1) visualizing transducer position; and 2)
    % localite coords RAS conversion (if using localite TriggerMarkers)
    % Input location: Setting folder locations for structural data
    filename_t1 = dir(fullfile(parameters.path.anat, parameters.path.t1_pattern));
    t1_header = niftiinfo(fullfile(filename_t1.folder, filename_t1.name));
    t1_image = niftiread(fullfile(filename_t1.folder, filename_t1.name));
    t1_grid_step_mm = t1_header.PixelDimensions(1);

    % ======================================================================= %
    %% LOAD LOCALITE TriggerMarkers FOR THIS SESSION
    % NAMING FORMAT IN LOCALITE: sub-XXX_sesA (or sesB or sesC)
    % Output: 
    %   - Session localite folder name
    %   - Average localite position per target (RAS)
    %   - Voxel target coordinates
    if localite_coordinates == 1
        % GET SESSION LOCALITE FOLDER NAME
        % ======================================================================= %
        % Normalize the region: strip any trailing "C0"/"C3"/"C6" style suffix
        % so 'caudate', 'caudateC0', 'caudateC3', 'caudateC6' all collapse to 'caudate'
        regionBase = regexprep(region, 'C\d+$', '');
        
        % Region -> session letter
        sesMap = containers.Map( ...
            {'pgACC','caudate','sham'}, ...
            {'A',    'B',      'C'});
        
        if ~isKey(sesMap, regionBase)
            error('Unrecognized region: %s', region);
        end
        
        sesTag = ['ses' sesMap(regionBase)];   % e.g. 'sesB'
        
        % Find folders whose name contains that session tag
        listing = dir(fullfile(localite_dir, ['*' sesTag '*']));
        listing = listing([listing.isdir]);
        listing = listing(~ismember({listing.name}, {'.', '..'}));
        
        if isempty(listing)
            error('No folder found for region "%s" (session %s) in %s', ...
                region, sesTag, localite_dir);
        elseif numel(listing) > 1
            warning('Multiple folders matched %s; using the first:', sesTag);
            disp({listing.name}')
        end
        
        % Subject localite data folder:
        sessGlob = fullfile(localite_dir, listing(1).name, 'Sessions', 'Session*');
        fprintf('Region "%s" -> %s\n', region, sessGlob);

        % Expand localite folder to time&date specific TMSTrigger folder
        s = dir(sessGlob);
        s = s([s.isdir]);                       % keep only directories
        s = s(~ismember({s.name}, {'.','..'})); % drop . and ..
        
        if isempty(s)
            error('No Session* folder found under %s', ...
                fullfile(localite_dir, listing(1).name, 'Sessions'));
        elseif numel(s) > 1
            warning('Multiple Session* folders; using the first: %s', s(1).name);
        end
        
        % Now build the real path with the resolved name
        targetFolder = fullfile(s(1).folder, s(1).name, 'TMSTrigger');

        %% LOAD LOCALITE DATA PER COIL
        % ======================================================================= %
        % Which coils does the Excel table say are used for this region/subject?
        % e.g. [0 3] or [1 2].  unique() returns them ascending -> lowest first.
        coil_numbers = unique(filtered_table.coil_nr(:))';      % ascending row vector
        assert(~isempty(coil_numbers), 'filtered_table.coil_nr is empty.');
        
        % Resolve EACH used coils OWN latest non-empty marker file, independently.
        % Coils are NOT guaranteed to share an export timestamp (e.g. Coil0 can be
        % ~100 ms off from Coil1-3), so a single shared timestamp must not be assumed.
        coilNameMap = containers.Map('KeyType','double','ValueType','char');
        for c = coil_numbers
            cdir = dir(fullfile(targetFolder, sprintf('TriggerMarkers_Coil%d_*.xml', c)));
            tsThisCoil = strings(0,1);
            for fi = 1:numel(cdir)
                fp = fullfile(targetFolder, cdir(fi).name);
                if xmlread(fp).getElementsByTagName('TriggerMarker').getLength == 0
                    continue                                    % skip empty exports (no markers)
                end
                tok = regexp(cdir(fi).name, '_(\d+)\.xml$', 'tokens', 'once');
                if ~isempty(tok)
                    tsThisCoil(end+1,1) = string(tok{1});  
                end
            end
            assert(~isempty(tsThisCoil), ...
                'No non-empty TriggerMarkers file found for Coil%d in %s', c, targetFolder);
        
            % Fixed-width YYYYMMDDHHMMSSmmm -> lexicographic sort == chronological,
            % and avoids double-precision loss on 17-digit timestamps.
            assert(numel(unique(strlength(tsThisCoil))) == 1, ...
                'Coil%d timestamps differ in length; string sort may misorder them.', c);
            tsThisCoil = sort(tsThisCoil);
            coilNameMap(c) = sprintf('TriggerMarkers_Coil%d_%s.xml', c, char(tsThisCoil(end)));
            fprintf('Coil%d -> %s\n', c, coilNameMap(c));
        end
        
        % Backward-compatible handles: lowest used coil first, then the next
        coil1_name = coilNameMap(coil_numbers(1));
        if numel(coil_numbers) >= 2
            coil2_name = coilNameMap(coil_numbers(2));
        else
            coil2_name = '';
        end
         
        % ===================================================================== %
        % SEPARATE & COMPUTE MEAN LOCALITE MATRIX PER TARGET PER COIL
        % Parse the chosen Coil TriggerMarkers file with readstruct and split it into
        % series. One series == one stimulation target, separated by gaps in the
        % recording time. 

        markertype              = 'TriggerMarkers';
        voxel_size              = t1_grid_step_mm;   % mm per voxel (deviation stats)

        % Distinct coil numbers actually present in the table
        coil_numbers = unique(filtered_table.coil_nr);   % e.g. [1; 2]
        n_coils      = numel(coil_numbers);
        
        % Map coil number -> Localite filename (index = coil number)
        coil_names = {coil1_name, coil2_name};   % coil_names{1}=coil 1, {2}=coil 2
        
        % Path struct so neuronav_convert_trigger_to_voxels can locate the T1
        pn = struct('data_prelocalite', parameters.path.anat);
        
        if n_coils == 1
            fprintf('Running sequential simulations with only 1 coil (coil %d)...\n', coil_numbers(1));
        else
            fprintf('Running sequential simulations alternating %d coils: %s\n', ...
                n_coils, mat2str(coil_numbers(:)'));
        end
        
        % Compute series statistics for each coil separately
        series_stats_by_coil = cell(1, n_coils);
        n_series             = zeros(1, n_coils);
        
        for coil_idx = 1:n_coils
            coil_num = coil_numbers(coil_idx);   % actual coil number from the table
        
            % rows of filtered_table belonging to this coil (for the count check)
            rows_this_coil = (filtered_table.coil_nr == coil_num);
        
            assert(isKey(coilNameMap, coil_num), ...
                'No marker file resolved for coil %d (referenced by the table).', coil_num);
            chosen_coil_path = fullfile(targetFolder, coilNameMap(coil_num));
            localite_struct  = readstruct(chosen_coil_path);
        
            series_stats_by_coil{coil_idx} = neuronav_compute_series_statistics_sequential( ...
                localite_struct, voxel_size, SI_dur, 'TriggerMarkers', ISI_thresh);
            n_series(coil_idx) = numel(series_stats_by_coil{coil_idx});
        
            fprintf('Localite: %d target series detected for %s (%s) [coil %d]\n', ...
                n_series(coil_idx), sub_str, region, coil_num);
        end
        
        % Overall check across all coils
        n_steps = numel(unique(filtered_table.stim_order));
        for ci = 1:n_coils
            if n_series(ci) < n_steps
                warning('Coil %d file has %d series but %d stim steps expected for %s %s.', ...
                    coil_numbers(ci), n_series(ci), n_steps, sub_str, region);
            end
        end
    end

    % ======================================================================= %
    %% Loop over the specific targets for sequential targeting
    % Load the correct transducer position
    for k = 1:height(filtered_table)
        % Extract values for this specific simulation
        Tpos = filtered_table.stim_order(k);  % This is 'pos1', 'pos2', etc.
        target = filtered_table.stimulation_target{k};  % This is 'L_pgACC_1', etc.
        PCD = filtered_table.transducer_model{k}; % This is IS_PCD15287_01001 (left) or IS_PCD15287_01002 (right).
        coil_this = filtered_table.coil_nr(k); % Which coil (localite tracker) is used for this stimulation

        fprintf('\nDetected: %s, F=%d, I=%d, Coil=%d\n', PCD, F_value, I_value, coil_this);

        %% Load calibration yaml file into parameters
        calibration_file = sprintf('%s~IGT_32_ch_comb_10_ch-F%dmm-I%dwpercm2.yaml', ...
                PCD, F_value, I_value);
        parameters.transducer = yaml.loadFile(fullfile(calibration_dir, calibration_file)).transducer;
        parameters.transducer = convert_yaml_to_numeric(parameters.transducer);
        parameters.transducer.focal_distance_ep = F_value; 
        parameters.placement.localite.tracker_to_bowl_mm = tracker_to_bowl_mm;

        %% Set full affix for this simulation.
        sim_target_name = filtered_table.Targeting_type{k};
        if contains(sim_target_name, '_')
            error('Targeting_type contains an underscore: "%s"', sim_target_name);
        end
        parameters.io.output_affix = sprintf('_%s_pos%d_F%d_I%d_r%s_%s_%s', target, Tpos, F_value, I_value, sim_res_affix, sim_target_name, simtype_aff);
        fprintf('Config affix: "%s" \n', parameters.io.output_affix)
        
        % ======================================================================= %
        %% Load coordinates
        if localite_coordinates == 0
            fprintf('USING EXCEL COORDINATES\n');
            % Get Target & Transducer locations from excel file
            % Target
            tar_pos_x = filtered_table.target_x(k);  
            tar_pos_y = filtered_table.target_y(k);
            tar_pos_z = filtered_table.target_z(k);
            % Transducer
            trans_pos_x = filtered_table.transducer_x(k);  
            trans_pos_y = filtered_table.transducer_y(k);
            trans_pos_z = filtered_table.transducer_z(k);

            parameters.transducer.trans_pos = [trans_pos_x, trans_pos_y, trans_pos_z];
            parameters.transducer.focus_pos = [tar_pos_x, tar_pos_y, tar_pos_z];
            fprintf('   [Transducer position] for "%s": [%d, %d, %d] vox \n', target, trans_pos_x, trans_pos_y, trans_pos_z)
            fprintf('   [Focus position] for "%s": [%d, %d, %d] vox \n', target, tar_pos_x, tar_pos_y, tar_pos_z)
            
            % Expected distance exitplane-target
            parameters.transducer.focal_distance_ep = norm(parameters.transducer.focus_pos - parameters.transducer.trans_pos);
            
            % For saving transducer, target and focus depth values
            expected_target_transducer_distance = parameters.transducer.focal_distance_ep;
            entry_target_pos = parameters.transducer.trans_pos;
            expected_focus_pos = '';
            target_transducer_distance = parameters.transducer.focus_pos;
        
        elseif localite_coordinates == 1
            fprintf('USING LOCALITE TRIGGERMARKER COORDINATES\n');
            % LOAD CORRECT TRANSDUCER SPECS FROM CALIBRATION FILE
            COIL_file = sprintf('%s~IGT_32_ch_comb_10_ch-F%dmm-I%dwpercm2.yaml', ...
                        PCD, F_value, I_value);
            fprintf('Using transducer calibration file: %s\n', COIL_file)
            COIL.transducer = yaml.loadFile(fullfile(calibration_dir, COIL_file)).transducer;
            COIL = convert_yaml_to_numeric(COIL);
            
            % --- Resolve which coil this target belongs to ---
            coil_num_this = filtered_table.coil_nr(k);                 % coil number for target k
            coil_idx_this = find(coil_numbers == coil_num_this, 1);    % position in series_stats_by_coil
            
            % Each coil's TriggerMarker file logs EVERY pulse of the WHOLE session, so every
            % coil file holds one series per global stimulation step, and those series are
            % time-aligned across coils (verified on the data).
            % => index by GLOBAL stim position, NOT by position within this coil's rows.
            [~, ~, stim_rank] = unique(filtered_table.stim_order);     % temporal rank 1..N
            series_idx = stim_rank(k);
            
            n_ser_this = numel(series_stats_by_coil{coil_idx_this});
            assert(series_idx <= n_ser_this, ...
                'Target %d (coil %d) maps to series %d, but that coil''s file only has %d series.', ...
                k, coil_num_this, series_idx, n_ser_this);
            
            this_series = series_stats_by_coil{coil_idx_this}{1, series_idx};


            %% Transform localite RAS to VOX
            [trans_pos, focus_pos, trans_pos_ras, focus_pos_ras] = ...
                localite_matrix_to_positions(this_series.matrix4d_mean, t1_header, parameters);

            parameters.transducer.trans_pos = trans_pos;
            parameters.transducer.focus_pos = focus_pos;
            fprintf('   [Transducer position] for "%s": [%d, %d, %d] vox \n', target, trans_pos(1), trans_pos(2), trans_pos(3))
            fprintf('   [Focus position] for "%s": [%d, %d, %d] vox \n', target, focus_pos(1), focus_pos(2), focus_pos(3))
         
        % LEGACY INSTRUMENT MARKERS (Localite v3.49 InstrumentMarkers):
        elseif localite_coordinates == 2
            fprintf('USING LOCALITE 3.4.9 INSTRUMENT MARKER\n');
            % Set T1 voxel size
            % Set expected_focal_distance_mm
            t1_grid_step_mm = t1_header.PixelDimensions(1);

            % Load IntrumentMarker.XML files
            % Load the most recent trigger mark file
            extract_dt = @(x) datetime(x.name(end-20:end-4),'InputFormat','yyyyMMddHHmmssSSS');
            instrument_loc = sprintf('%s/InstrumentMarker*.xml', localite_loc);
            TriggerMarker_file = dir(instrument_loc);
            
            if isempty(TriggerMarker_file)
                error('Localite file `%s` cannot be found', instrument_loc)
            end
            
            % Filter out files that are not InstrumentMarker files
            TriggerMarker_file = TriggerMarker_file(contains({TriggerMarker_file.name}, 'InstrumentMarker'));
            
            % Select the most recent file and extract the coordinates
            [~,idx] = sort([arrayfun(extract_dt,TriggerMarker_file)],'descend');
            TriggerMarker_file = TriggerMarker_file(idx);
            recent_InstrumentMarker_file = xml2struct(fullfile(TriggerMarker_file(1).folder, TriggerMarker_file(1).name));
            
            % Identify which trigger marker to load from xml file
            idy = [];
            markers = recent_InstrumentMarker_file.InstrumentMarkerList.InstrumentMarker;
            for x = 1:numel(markers)
                desc = markers{1,x}.Marker.Attributes.description;  
                if strcmp(desc, target)
                    idy = x;
                    break
                end
            end
        
            % Give error if name is not used/found in localite file.
            if isempty(idy)
                error('No marker with description "%s" found.', target);
            end
            
            % Load trigger markers and turn them into doubles (i.e.,
            % InstrumentMarker)
            trigger_markers = recent_InstrumentMarker_file.InstrumentMarkerList.InstrumentMarker{1,idy}.Marker.Matrix4D.Attributes;
            trigger_marker_fieldnames = fieldnames(trigger_markers);
            for m = 1:length(trigger_marker_fieldnames)
                trigger_markers.(trigger_marker_fieldnames{m}) = str2double(trigger_markers.(trigger_marker_fieldnames{m}));
            end
            
            % Load instrument markers
            matrix_flat = struct2cell(trigger_markers);
            coord_matrix = reshape(cell2mat(matrix_flat)', 4, 4)';
            
            % Extract Reference Position and Direction Vectors
            % Reference position: translation vector from neuronavigation reference point.
            reference_pos = coord_matrix(:, 4); 

            % Direction vector pointing from coil center towards head.
            reference_center_to_head = coord_matrix(:, 1);
        
            % Compute Transducer and Focus Positions in RAS Space
            % Calculate total distance between reference and transducer face
            parameters.reference_transducer_distance_mm = -(parameters.transducer.curv_radius_mm - parameters.transducer.dist_to_plane_mm) - coupler_to_transducer_distance;
           
            % Calculate transducer position relative to reference point.
            trans_pos_ras = reference_pos + parameters.reference_transducer_distance_mm * reference_center_to_head;
        
            % Calculate focus position relative to transducer position.
            focus_pos_ras = trans_pos_ras + parameters.expected_focal_distance_mm * reference_center_to_head;
        
            % Convert Positions from RAS Space to Voxel Space
            % Use MRI header's transformation matrix to convert RAS coordinates to voxel coordinates.
            trans_pos = round(t1_header.Transform.T' \ trans_pos_ras);  % Transducer position in voxel space.
            focus_pos = round(t1_header.Transform.T' \ focus_pos_ras);  % Focus position in voxel space.
        
            % Extract x, y, z components of positions (ignore homogeneous coordinate).
            trans_pos = trans_pos(1:3);
            focus_pos = focus_pos(1:3);
            parameters.transducer.trans_pos = trans_pos;
            parameters.transducer.focus_pos = focus_pos;
            fprintf('   [Transducer position] for "%s": [%d, %d, %d] vox \n', target, trans_pos(1), trans_pos(2), trans_pos(3))
            fprintf('   [Focus position] for "%s": [%d, %d, %d] vox \n', target, focus_pos(1), focus_pos(2), focus_pos(3))
        
        else
            error('Value of "localite_coordinates" should be set to either 0, 1 or 2.')
        end
        
        %% Preview transducer location
        if preview_transducer_loc == 1
            % Compensate for 1-based indexing in Matlab
            parameters.transducer.trans_pos = parameters.transducer.trans_pos + 1;
            parameters.transducer.focus_pos = parameters.transducer.focus_pos + 1;

            % Flip the coordinates around for later use
            transducer_coordinates = parameters.transducer.trans_pos';
            focus_coordinates = parameters.transducer.focus_pos';
            
            % Makes a different slice depending on the target
            if contains(region, 'pgACC')
                slice_dim_right_figure = 1;
                slice_dim_left_figure = 3;
            else
                slice_dim_right_figure = 2;
                slice_dim_left_figure = 3;
            end
            
            % Create Figure
            figure;
            hImage = imshowpair(...
                plot_t1_with_transducer(t1_image, t1_header.PixelDimensions(1), transducer_coordinates, focus_coordinates, parameters, 'slice_dim', slice_dim_left_figure), ...
                plot_t1_with_transducer(t1_image, t1_header.PixelDimensions(1), transducer_coordinates, focus_coordinates, parameters, 'slice_dim', slice_dim_right_figure), ...
                'montage');
            hAxes = get(hImage, 'Parent');
            title(hAxes, sprintf('sub-%03d %s [%g; %g; %g]', subject_id, target, transducer_coordinates(:,1)-1)); % -1 is at the end to remove compensation of 1-based indexing in plot title
        end
        
        if run_PLANTUS == 1
            error('WORK IN PROGRESS FOR THIS PIPELINE... PLANTUS does not work yet in this specific pipelin.')
            parameters.placement.mode = 'plantus';
            parameters.placement.plantus.mni_target_mm = parameters.transducer.trans_pos;
            parameters.placement.plantus.target_name = region;
            parameters.placement.plantus.focal_distance_list = [parameters.transducer.focal_distance_ep];
            parameters.placement.plantus.flhm_list = [parameters.transducer.focal_distance_bowl];
        end

        %% DEFINE SEQUENTIAL STIMULATION
        if run_sequential == 1
            parameters.io.overwrite_files = 'always';

            % First simulation: store as first_config
            if consecutive_simulation_number == 1
                first_config = parameters;
                first_config.modules.run_posthoc_water_sims = 1;
                % fprintf('   %s transducer location: [%g %g %g] (first_config)\n\n', ...
                %     target, first_config.transducer.trans_pos(:));
                cfg_name = sprintf('config_%d', consecutive_simulation_number);
                % Define where adopted heatmap will be stored
                first_config.io.dir_output = parameters.io.dir_output;

            % Subsequent simulations: store current config
            else
                cfg_name  = sprintf('config_%d', consecutive_simulation_number);
                prev_name = sprintf('config_%d', consecutive_simulation_number - 1);
                sequential_configs.(cfg_name) = parameters;
                
                if consecutive_simulation_number == 2
                    prev_cfg = first_config;
                    
                    % Point adopted_heatmap to previous simulation's output
                    %   HEATING
                    sequential_configs.(cfg_name).io.adopted_heatmap = fullfile(first_config.io.dir_output, ...
                        sprintf('sub-%03d_layered_T1w%s_heating_end.nii.gz', subject_id, first_config.io.output_affix));
                    %   CEM43
                    if parameters.thermal.cem43_iso == 1
                        sequential_configs.(cfg_name).io.adopted_CEM43 = fullfile(first_config.io.dir_output, ...
                            sprintf('sub-%03d_layered_T1w%s_CEM43_iso_end.nii.gz', subject_id, first_config.io.output_affix));
                    else
                        sequential_configs.(cfg_name).io.adopted_CEM43 = fullfile(first_config.io.dir_output, ...
                            sprintf('sub-%03d_layered_T1w%s_CEM43_end.nii.gz', subject_id, first_config.io.output_affix));
                    end
                end

                % Resolve previous config
                if consecutive_simulation_number > 2
                    prev_cfg = sequential_configs.(prev_name);  % == first_config when sim 2
                    
                    % Point adopted_heatmap to previous simulation's output
                    %   HEATING
                    sequential_configs.(cfg_name).io.adopted_heatmap = fullfile(first_config.io.dir_output, ...
                        sprintf('sub-%03d_layered_T1w%s_heating_end.nii.gz', subject_id, first_config.io.output_affix));
                    %   CEM43
                    if parameters.thermal.cem43_iso == 1
                        sequential_configs.(cfg_name).io.adopted_CEM43 = fullfile(first_config.io.dir_output, ...
                            sprintf('sub-%03d_layered_T1w%s_CEM43_iso_end.nii.gz', subject_id, first_config.io.output_affix));
                    else
                        sequential_configs.(cfg_name).io.adopted_CEM43 = fullfile(first_config.io.dir_output, ...
                            sprintf('sub-%03d_layered_T1w%s_CEM43_end.nii.gz', subject_id, first_config.io.output_affix));
                    end
                end
                
                if localite_coordinates == 1
                    sequential_configs.(cfg_name).transducer.trans_pos = trans_pos;
                    sequential_configs.(cfg_name).transducer.focus_pos = focus_pos;
                end

                % fprintf('   %s transducer location: [%g %g %g]\n\n', ...
                %     target, sequential_configs.(cfg_name).transducer.trans_pos(:));
            end

            consecutive_simulation_number = consecutive_simulation_number + 1;
            options.sequential_configs = sequential_configs;
        end

        %% Save the actual Entrytarget-Transducerfocus distance
        if save_json == 1
            focus_results(end+1).subject = sub_str;
            focus_results(end).region= region;
            focus_results(end).target = target;
            focus_results(end).transducer = PCD;
            focus_results(end).transducer_pos = parameters.transducer.trans_pos;
            focus_results(end).expected_focus_pos = parameters.transducer.focus_pos;
            %focus_results(end).entry_target_pos = entry_target_pos;
            %focus_results(end).expected_distance = expected_target_transducer_distance;
            %focus_results(end).actual_distance = target_transducer_distance;

            disp('saving json file.')
            json_file = fullfile(json_dir, sprintf('focus_results_%s.json', parameters.io.output_affix));
        
            jsonText = jsonencode(focus_results);
        
            fid = fopen(json_file,'w');
            fprintf(fid, '%s', jsonText);
            fclose(fid);
        end

        % ======================================================================= %
        %% Start the Acoustic simulation
        if run_heating == 0
            if run_sims == 1
                if strcmp(submit, 'slurm') == true
                    parameters.simulation.interactive = 0;
                    parameters.io.overwrite_files = 'always';
                    prestus_pipeline_start(parameters); 
                else
                    error('Submit medium does not correspond to available options.')
                end
                
            end
            
        end
    end

    
    %% Start the Sequential heating simulation
    if run_heating == 1 && run_sequential == 1 && run_sims == 1
        % Submit sequential heating sims job.
        first_config.simulation.interactive = 0;
        prestus_pipeline_start(...
            first_config, ...
            options);
    end
end

disp('Script finished successfully.')

%% ===========================================================
%% FUNCTIONS
%% ===========================================================
%% CONVERT YAML TO NUMERIC
function s = convert_yaml_to_numeric(s)
    fields = fieldnames(s);
    
    for i = 1:length(fields)
        field = fields{i};
        value = s.(field);
        
        % *** Recurse into nested structs ***
        if isstruct(value)
            s.(field) = convert_yaml_to_numeric(value);
        
        % Handle cell arrays
        elseif iscell(value)
            if all(cellfun(@isnumeric, value))
                s.(field) = cell2mat(value);
            elseif length(value) == 1 && isnumeric(value{1})
                s.(field) = value{1};
            elseif all(cellfun(@ischar, value))
                try
                    s.(field) = cellfun(@str2double, value);
                catch
                    % Keep as is if conversion fails
                end
            end
        
        % Handle strings that look like numbers
        elseif ischar(value)
            num_val = str2double(value);
            if ~isnan(num_val)
                s.(field) = num_val;
            end
        end
    end
end

