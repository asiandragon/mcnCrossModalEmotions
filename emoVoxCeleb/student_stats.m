%function student_stats(varargin)
%STUDENT_STATS - compute the statistics for student predictions
%   STUDENT_STATS(VARARGIN) computes the similarity bewteen
%   predictions made by the student model (which operates on voices)
%   and those made by the teacher (which operates on faces) across
%   the EmoVoxCeleb dataset.
%
%   STUDENT_STATS(..'name', value) accepts the following options:
%
%   `refresh` :: false
%    If true, recomputes all features on EmoVoxCeleb using the student
%    model.
%
%   `partition` :: 'unheardTest'
%    The partition of the data to visualize (can be one of 'train',
%    'unheardVal', 'unheardTest', 'heardVal' and 'heardTest').
%
%   `visHist` :: false
%    If true, visualise the distriution of dominant predictions made by
%    the teacher.
%
% Copyright (C) 2018 Samuel Albanie
% Licensed under The MIT License [see LICENSE.md for details]

  opts.refresh = false ;
  opts.visHist = false ;
  opts.ignore = {'contempt', 'disgust'} ;
  opts.figDir = fullfile(fileparts(mfilename('fullpath')), 'figs') ;
  opts.cachePath = fullfile(vl_rootnn, ...
                       'data/mcnCrossModalEmotions/cache/student-stats.mat') ;
  opts.partition = 'all' ;
  opts.expRoot = fullfile(vl_rootnn, '/data/xEmo18') ;
  opts.teacher = 'senet50_ft-dag-distributions-CNTK-dropout-0.5-aug' ;
  %opts = vl_argparse(opts, varargin) ;

  if opts.refresh
    modelPairs = getAudioModels('teacherType', 'CNTK') ;
    modelPair = modelPairs{1} ;
    modelName = modelPair{1} ; numEmotions = modelPair{2} ;
    modelDir = fullfile(opts.expRoot, modelName) ;
    featPath = compute_audio_feats_for_dataset(...
                                    'targetDataset', 'emoceleb', ...
                                    'teacher', teacher, ...
                                    'modelDir', modelDir, ...
                                    'clobber', true, ...
                                    'manualEpoch', false, ...
                                    'numEmotions', numEmotions) ;
  else
    % for now, this will be hardcoded.
    featPath = fullfile(vl_rootnn, 'data/xEmo18/emoceleb_storedFeatsAudio/voxceleb-senet50_ft-dag-distributions-CNTK-dropout-0.5-aug-vggm_bn_identif-hot-cross-ent-scratch-1-4sec-8emo-wavLogits-agg-max-temp2-unbalanced-logspace-logits-epoch280.mat') ;
  end

  stored = load(featPath) ;
  % note that confusingly, the student predictions are stored as
  % the faceLogits attribute.
  studentLogits = vertcat(stored.faceLogits{:}) ;
  [~,maxLogits] = max(studentLogits, [], 2) ;

  if opts.visHist
    histogram(maxLogits) ;
    title('histogram of dominant emotions (predicted by student)') ;
    if exist('zs_dispFig', 'file'), zs_dispFig ; end
   end

  if ~exist('loadedImdb', 'var')
    fprintf('loading EmoVoxCeleb Imdb...') ; tic ;
    loadedImdb = fetch_emoceleb_imdb() ;
    fprintf('done in %g s\n', toc) ;
  end

  setIdx = 1:5 ;
  keys = {'train', 'unheardVal', 'unheardTest', 'heardVal', 'heardTest'} ;
  setMap = containers.Map(keys, setIdx) ;

  if ~strcmp(opts.partition, 'all')
    partitions = {opts.partition} ;
  else
    partitions = keys ;
  end

  for ii = 1:numel(partitions)
    partition = partitions{ii} ;
    fprintf('compute stats for %s (%d/%d)...\n', ...
                              partition, ii, numel(partitions)) ;

    % compute mean average precision, using max logits as the target label
    keep = (loadedImdb.images.intersectSet == setMap(partition)) ;
    normedLogits = vl_nnsoftmaxt(studentLogits, 'dim', 2) ;
    subsetLogits = normedLogits(keep,:) ;
    [~,teacherMaxLogits] = cellfun(@(y) max(max(y,[], 1)), ...
                                           stored.wavLogits(keep)) ;

    if opts.visHist %  visualise histogram if required
      histogram(teacherMaxLogits) ;
      if exist('zs_dispFig', 'file'), zs_dispFig ; end
    end

    % compute AP per class and visualise PR
    if ~exist(opts.figDir, 'dir'), mkdir(opts.figDir) ; end
    emotions = x.meta.emotions ;
    auc = zeros(1,numel(emotions)) ;
    for jj = 1:numel(emotions)
      classIdx = jj ;
      labels = -1 * ones(1, numel(teacherMaxLogits)) ;
      labels(teacherMaxLogits == classIdx) = 1 ;
      scores = subsetLogits(:,classIdx) ;
      [~,~,info] = vl_roc(labels, scores) ;
      auc(jj) = info.auc ;

      vl_roc(labels, scores) ; % visualise ROC curve if required
      title(sprintf('%s (%s)', emotions{jj}, partition)) ;
      destPath = fullfile(opts.figDir, ...
                     sprintf('%s-%s.jpg', emotions{jj}, partition)) ;
      if ~ismember(emotions{jj}, opts.ignore)
        saveas(1, destPath) ;
        if exist('zs_dispFig', 'file'), zs_dispFig ; end
      end
    end

    for jj = 1:numel(emotions)
      fprintf('%s: %g\n', emotions{jj}, auc(jj)) ;
    end

    if ~exist(fileparts(opts.cachePath), 'dir')
      mkdir(fileparts(opts.cachePath)) ;
    end
    if ~exist(opts.cachePath, 'file')
      cache.emotions = emotions ;
    else
      cache = load(opts.cachePath) ;
    end

    % compute mean average precision for emotions that are represented
    representedEmotions = unique(teacherMaxLogits) ;
    meanAuc = mean(auc(representedEmotions)) ;
    fprintf('meanAuc: %g\n', meanAuc) ;
    if ~isfield(cache, partition)
      cache.(partition) = auc ;
    end
    save(opts.cachePath, '-struct', 'cache') ;
  end