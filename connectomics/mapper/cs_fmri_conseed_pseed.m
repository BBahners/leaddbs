function cs_fmri_conseed_pseed(dfold,cname,sfile,cmd,writeoutsinglefiles,outputfolder,outputmask)

tic

% if ~isdeployed
%     addpath(genpath('/autofs/cluster/nimlab/connectomes/software/lead_dbs'));
%     addpath('/autofs/cluster/nimlab/connectomes/software/spm12');
% end

if ~exist('writeoutsinglefiles','var')
    writeoutsinglefiles=0;
else
    if ischar(writeoutsinglefiles)
        writeoutsinglefiles=str2double(writeoutsinglefiles);
    end
end


if ~exist('dfold','var')
    dfold=''; % assume all data needed is stored here.
else
    if ~strcmp(dfold(end),filesep)
        dfold=[dfold,filesep];
    end
end

disp(['Connectome dataset: ',cname,'.']);
    ocname=cname;
if ismember('>',cname)
    delim=strfind(cname,'>');
    subset=cname(delim+1:end);
    cname=cname(1:delim-1);
end
prefs=ea_prefs;
dfoldsurf=[dfold,'fMRI',filesep,cname,filesep,'surf',filesep];
dfoldvol=[dfold,'fMRI',filesep,cname,filesep,'vol',filesep]; % expand to /vol subdir.

d=load([dfold,'fMRI',filesep,cname,filesep,'dataset_info.mat']);
dataset=d.dataset;
clear d;
if exist('outputmask','var')
    if ~isempty(outputmask)
        omask=ea_load_nii(outputmask);
        omaskidx=find(omask.img(:));
        [~,maskuseidx]=ismember(omaskidx,dataset.vol.outidx);
    else
        omaskidx=dataset.vol.outidx;
        maskuseidx=1:length(dataset.vol.outidx);
    end
else
    omaskidx=dataset.vol.outidx; % use all.
    maskuseidx=1:length(dataset.vol.outidx);
end

owasempty=0;
if ~exist('outputfolder','var')
    outputfolder=ea_getoutputfolder(sfile,ocname);
    owasempty=1;
else
    if isempty(outputfolder) % from shell wrapper.
        outputfolder=ea_getoutputfolder(sfile,ocname);
        owasempty=1;
    end
    if ~strcmp(outputfolder(end),filesep)
        outputfolder=[outputfolder,filesep];
    end
end

if strcmp(sfile{1}(end-2:end),'.gz')
    %gunzip(sfile)
    %sfile=sfile(1:end-3);
    usegzip=1;
else
    usegzip=0;
end

for s=1:size(sfile,1)
    if size(sfile(s,:),2)>1
        dealingwithsurface=1;
    else
        dealingwithsurface=0;
    end
    for lr=1:size(sfile(s,:),2)
        if exist(ea_niigz(sfile{s,lr}),'file')
            seed{s,lr}=ea_load_nii(ea_niigz(sfile{s,lr}));
        else
            if size(sfile(s,:),2)==1
                ea_error(['File ',ea_niigz(sfile{s,lr}),' does not exist.']);
            end
            switch lr
                case 1
                    sidec='l';
                case 2
                    sidec='r';
            end
            seed{s,lr}=dataset.surf.(sidec).space; % supply with empty space
            seed{s,lr}.fname='';
            seed{s,lr}.img(:)=0;
        end
        if ~isequal(seed{s,lr}.mat,dataset.vol.space.mat) && (~dealingwithsurface)
            oseedfname=seed{s,lr}.fname;

            try
                seed{s,lr}=ea_conformseedtofmri(dataset,seed{s,lr});
            catch
                keyboard
            end
            seed{s,lr}.fname=oseedfname; % restore original filename if even unneccessary at present.
        end

        [~,seedfn{s,lr}]=fileparts(sfile{s,lr});
        if dealingwithsurface
            sweights=seed{s,lr}.img(:);
        else
            sweights=seed{s,lr}.img(dataset.vol.outidx);
        end
        sweights(isnan(sweights))=0;
        sweights(isinf(sweights))=0; %

        sweights(abs(sweights)<0.0001)=0;
        sweights=double(sweights);

        try
            options=evalin('caller','options');
        end
        if exist('options','var')
            if strcmp(options.lcm.seeddef,'parcellation')
                sweights=round(sweights);
            end
        end
        % assure sum of sweights is 1
        %sweights(logical(sweights))=sweights(logical(sweights))/abs(sum(sweights(logical(sweights))));
        sweightmx=repmat(sweights,1,1);

        sweightidx{s,lr}=find(sweights);
        sweightidxmx{s,lr}=double(sweightmx(sweightidx{s,lr},:));
    end
end

numseed=s;
try
    options=evalin('caller','options');
end
if exist('options','var')
    if strcmp(options.lcm.seeddef,'parcellation') % expand seeds to define
        if ismember(cmd,{'seed','pseed','pmap'})
            ea_error('Command not supported for parcellation as input.');
        end
        [ixx]=unique(round(sweights)); ixx(ixx==0)=[];
        numseed=length(ixx);
        for parcseed=ixx'
            sweightidx{parcseed+1,1}=sweightidx{1,1}(sweightidxmx{1,1}==parcseed);
            sweightidxmx{parcseed+1,1}=ones(size(sweightidx{parcseed+1,1},1),1);
        end
        sweightidx(1)=[]; % original parcellation which has now been expanded to single seeds
        sweightidxmx(1)=[]; % original parcellation which has now been expanded to single seeds
        sfile=repmat(sfile,size(sweightidx,1),1);
    end
end

disp([num2str(numseed),' seeds, command = ',cmd,'.']);

numSubUse=length(dataset.vol.subIDs);

if ~exist('subset','var') % use all subjects
    usesubjects = 1:numSubUse;
else
    for ds=1:length(dataset.subsets)
        if strcmp(subset,dataset.subsets(ds).name)
            usesubjects=dataset.subsets(ds).subs;
            break
        end
    end
    numSubUse = length(usesubjects);
end

numVoxUse = length(omaskidx);

% init vars:
for s=1:numseed
    fX{s}=nan(numVoxUse,numSubUse);
    rhfX{s}=nan(10242,numSubUse);
    lhfX{s}=nan(10242,numSubUse);
end

isSurfAvail = isfield(dataset,'surf');
includeSurf = prefs.lcm.includesurf;

disp('Iterating through subjects...');
for i=1:numseed
    seedFilename = seedfn{i};

    if size(sfile(i,:),2)>1
        isROISurf = true;
    else
        isROISurf = false;
    end

    fXi = nan(numVoxUse,numSubUse);
    lh_fXi = nan(10242,numSubUse);
    rh_fXi = nan(10242,numSubUse);

    parfor subj = 1:numSubUse % iterate across subjects
        mcfi = usesubjects(subj);
        disp(['Subject ', num2str(mcfi, '%04d'),'/',num2str(numSubUse,'%04d'),'...']);
        howmanyruns=ea_cs_dethowmanyruns(dataset,mcfi);
        thiscorr = nan(numVoxUse,howmanyruns);
        lsThisCorr = nan(10242,howmanyruns);
        rsThisCorr = nan(10242,howmanyruns);

        subIDVol = dataset.vol.subIDs{mcfi};

        if isSurfAvail && includeSurf
            subIDSurfL = dataset.surf.l.subIDs{mcfi};
            subIDSurfR = dataset.surf.r.subIDs{mcfi};
        end

        for run=1:howmanyruns
            gmtcstruc = load([dfoldvol,subIDVol{run+1}]);
            gmtc = single(gmtcstruc.gmtc);

            if isSurfAvail && includeSurf
                ls_struc = load([dfoldsurf,subIDSurfL{run+1}]);
                rs_struc = load([dfoldsurf,subIDSurfR{run+1}]);

                ls_gmtc = single(ls_struc.gmtc);
                rs_gmtc = single(rs_struc.gmtc);
            end

            if isROISurf % dealing with surface seed
                all_stc = nan(numseed,size(gmtc,2));
                for subseed = 1:numseed
                    all_stc(subseed,:) = nanmean([ls_gmtc(sweightidx{subseed,1},:).*repmat(sweightidxmx{subseed,1},1,size(ls_gmtc,2));...
                                                  rs_gmtc(sweightidx{subseed,2},:).*repmat(sweightidxmx{subseed,2},1,size(rs_gmtc,2))],1);
                end
            else % volume seed
                all_stc = nan(numseed,size(gmtc,2));
                for subseed = 1:numseed
                    all_stc(subseed,:) = nanmean(gmtc(sweightidx{subseed},:).*repmat(sweightidxmx{subseed},1,size(gmtc,2)),1);
                end
            end

            os=1:numseed; os(i)=[]; % remaining seeds
            [~,~,stc]=regress(all_stc(i,:)',addone(all_stc(os,:)')); % regress out other time series from current one
            stc=stc';

            %correlate seed average time course to time courses of voxels specified by mask)
            thiscorr(:,run)=corr(stc',gmtc(maskuseidx,:)','type','Pearson');
            if isSurfAvail && includeSurf
                lsThisCorr(:,run)=corr(stc',ls_gmtc','type','Pearson');
                rsThisCorr(:,run)=corr(stc',rs_gmtc','type','Pearson');
            end
        end

        % may be conerns if usesubjects is a subset and does not follow a nice 1:numsubs sequence for indexing purposes with mcfi
        fXi(:,subj)=mean(thiscorr,2);
        if isSurfAvail && includeSurf
            lh_fXi(:,subj)=mean(lsThisCorr,2);
            rh_fXi(:,subj)=mean(rsThisCorr,2);
        end

        if writeoutsinglefiles
            ccmap=dataset.vol.space;
            ccmap.fname=[outputfolder,seedFilename,'_',subIDVol{1},'_corr.nii'];
            ccmap.img=single(ccmap.img);
            ccmap.img(omaskidx)=fXi(:,subj);
            ccmap.dt=[16,0];
            spm_write_vol(ccmap,ccmap.img);

            % surfs, too:
            if isSurfAvail && includeSurf
                ccmap=dataset.surf.l.space;
                ccmap.fname=[outputfolder,seedFilename,'_',subIDVol{1},'_corr_surf_lh.nii'];
                ccmap.img=single(ccmap.img);
                ccmap.img(:,:,:,2:end)=[];
                ccmap.img(:)=lh_fXi(:,subj);
                ccmap.dt=[16,0];
                spm_write_vol(ccmap,ccmap.img);

                ccmap=dataset.surf.r.space;
                ccmap.fname=[outputfolder,seedFilename,'_',subIDVol{1},'_corr_surf_rh.nii'];
                ccmap.img=single(ccmap.img);
                ccmap.img(:,:,:,2:end)=[];
                ccmap.img(:)=rh_fXi(:,subj);
                ccmap.dt=[16,0];
                spm_write_vol(ccmap,ccmap.img);
            end
        end
    end

    fX{i} = fXi;
    if isSurfAvail
        lhfX{i} = lh_fXi;
        rhfX{i} = rh_fXi;
    end
end
disp('Done.');

for s=1:size(seedfn,1) % subtract 1 in case of pmap command
    if owasempty
       outputfolder=ea_getoutputfolder({sfile{s}},ocname);
    end
    % export mean
    M=ea_nanmean(fX{s}',1);
    mmap=dataset.vol.space;
    mmap.dt=[16,0];
    mmap.img(:)=0;
    mmap.img=single(mmap.img);
    mmap.img(omaskidx)=M;

    mmap.fname=[outputfolder,seedfn{s},'_func_',cmd,'_AvgR.nii'];
    ea_write_nii(mmap);
    if usegzip
        gzip(mmap.fname);
        delete(mmap.fname);
    end

    % export variance
    M=ea_nanvar(fX{s}');
    mmap=dataset.vol.space;
    mmap.dt=[16,0];
    mmap.img(:)=0;
    mmap.img=single(mmap.img);
    mmap.img(omaskidx)=M;

    mmap.fname=[outputfolder,seedfn{s},'_func_',cmd,'_VarR.nii'];
    ea_write_nii(mmap);
    if usegzip
        gzip(mmap.fname);
        delete(mmap.fname);
    end

    if isSurfAvail && includeSurf
        % lh surf
        lM=ea_nanmean(lhfX{s}');
        lmmap=dataset.surf.l.space;
        lmmap.dt=[16,0];
        lmmap.img=zeros([size(lmmap.img,1),size(lmmap.img,2),size(lmmap.img,3)]);
        lmmap.img=single(lmmap.img);
        lmmap.img(:)=lM(:);
        lmmap.fname=[outputfolder,seedfn{s},'_func_',cmd,'_AvgR_surf_lh.nii'];
        ea_write_nii(lmmap);
        if usegzip
            gzip(lmmap.fname);
            delete(lmmap.fname);
        end

        % rh surf
        rM=ea_nanmean(rhfX{s}');
        rmmap=dataset.surf.r.space;
        rmmap.dt=[16,0];
        rmmap.img=zeros([size(rmmap.img,1),size(rmmap.img,2),size(rmmap.img,3)]);
        rmmap.img=single(rmmap.img);
        rmmap.img(:)=rM(:);
        rmmap.fname=[outputfolder,seedfn{s},'_func_',cmd,'_AvgR_surf_rh.nii'];
        ea_write_nii(rmmap);
        if usegzip
            gzip(rmmap.fname);
            delete(rmmap.fname);
        end
    end

    % fisher-transform:
    fX{s}=atanh(fX{s});
    if isSurfAvail && includeSurf
        lhfX{s}=atanh(lhfX{s});
        rhfX{s}=atanh(rhfX{s});
    end
    % export fz-mean

    M=nanmean(fX{s}');
    mmap=dataset.vol.space;
    mmap.dt=[16,0];
    mmap.img(:)=0;
    mmap.img=single(mmap.img);
    mmap.img(omaskidx)=M;
    mmap.fname=[outputfolder,seedfn{s},'_func_',cmd,'_AvgR_Fz.nii'];
    spm_write_vol(mmap,mmap.img);
    if usegzip
        gzip(mmap.fname);
        delete(mmap.fname);
    end
    if isSurfAvail && includeSurf
        % lh surf
        lM=nanmean(lhfX{s}');
        lmmap=dataset.surf.l.space;
        lmmap.dt=[16,0];
        lmmap.img=zeros([size(lmmap.img,1),size(lmmap.img,2),size(lmmap.img,3)]);
        lmmap.img=single(lmmap.img);
        lmmap.img(:)=lM(:);
        lmmap.fname=[outputfolder,seedfn{s},'_func_',cmd,'_AvgR_Fz_surf_lh.nii'];
        ea_write_nii(lmmap);
        if usegzip
            gzip(lmmap.fname);
            delete(lmmap.fname);
        end

        % rh surf
        rM=nanmean(rhfX{s}');
        rmmap=dataset.surf.r.space;
        rmmap.dt=[16,0];
        rmmap.img=zeros([size(rmmap.img,1),size(rmmap.img,2),size(rmmap.img,3)]);
        rmmap.img=single(rmmap.img);
        rmmap.img(:)=rM(:);
        rmmap.fname=[outputfolder,seedfn{s},'_func_',cmd,'_AvgR_Fz_surf_rh.nii'];
        ea_write_nii(rmmap);
        if usegzip
            gzip(rmmap.fname);
            delete(rmmap.fname);
        end
    end

    % export T

    [~,~,~,tstat]=ttest(fX{s}');
    tmap=dataset.vol.space;
    tmap.img(:)=0;
    tmap.dt=[16,0];
    tmap.img=single(tmap.img);

    tmap.img(omaskidx)=tstat.tstat;

    tmap.fname=[outputfolder,seedfn{s},'_func_',cmd,'_T.nii'];
    spm_write_vol(tmap,tmap.img);
    if usegzip
        gzip(tmap.fname);
        delete(tmap.fname);
    end

    if isSurfAvail && includeSurf
        % lh surf
        [~,~,~,ltstat]=ttest(lhfX{s}');
        lmmap=dataset.surf.l.space;
        lmmap.dt=[16,0];
        lmmap.img=zeros([size(lmmap.img,1),size(lmmap.img,2),size(lmmap.img,3)]);
        lmmap.img=single(lmmap.img);
        lmmap.img(:)=ltstat.tstat(:);
        lmmap.fname=[outputfolder,seedfn{s},'_func_',cmd,'_T_surf_lh.nii'];
        ea_write_nii(lmmap);
        if usegzip
            gzip(lmmap.fname);
            delete(lmmap.fname);
        end

        % rh surf
        [~,~,~,rtstat]=ttest(rhfX{s}');
        rmmap=dataset.surf.r.space;
        rmmap.dt=[16,0];
        rmmap.img=zeros([size(rmmap.img,1),size(rmmap.img,2),size(rmmap.img,3)]);
        rmmap.img=single(rmmap.img);
        rmmap.img(:)=rtstat.tstat(:);
        rmmap.fname=[outputfolder,seedfn{s},'_func_',cmd,'_T_surf_rh.nii'];
        ea_write_nii(rmmap);
        if usegzip
            gzip(rmmap.fname);
            delete(rmmap.fname);
        end
    end
end


toc


function s=ea_conformseedtofmri(dataset,s)
td=tempdir;
dataset.vol.space.fname=[td,'tmpspace.nii'];
ea_write_nii(dataset.vol.space);
s.fname=[td,'tmpseed.nii'];
ea_write_nii(s);

ea_conformspaceto([td,'tmpspace.nii'],[td,'tmpseed.nii']);
s=ea_load_nii(s.fname);
delete([td,'tmpspace.nii']);
delete([td,'tmpseed.nii']);


function howmanyruns=ea_cs_dethowmanyruns(dataset,mcfi)
if strcmp(dataset.type,'fMRI_matrix')
    howmanyruns=1;
else
    howmanyruns=length(dataset.vol.subIDs{mcfi})-1;
end

function X=addone(X)
X=[ones(size(X,1),1),X];

function [mat,loaded]=ea_getmat(mat,loaded,idx,chunk,datadir)

rightmat=(idx-1)/chunk;
rightmat=floor(rightmat);
rightmat=rightmat*chunk;
if rightmat==loaded;
    return
end

load([datadir,num2str(rightmat),'.mat']);
loaded=rightmat;

