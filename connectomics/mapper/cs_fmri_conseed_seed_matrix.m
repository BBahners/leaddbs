function cs_fmri_conseed_seed_matrix(dfold,cname,sfile,cmd,writeoutsinglefiles,outputfolder,outputmask)

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
        ea_error('Command not supported for parcellation as input.');
    end
end

disp([num2str(numseed),' seeds, command = ',cmd,'.']);

pixdim=length(dataset.vol.outidx);

numSubUse=length(dataset.vol.subIDs);

if ~exist('subset','var') % use all subjects
    usesubjects=1:numSubUse;
else
    for ds=1:length(dataset.subsets)
        if strcmp(subset,dataset.subsets(ds).name)
            usesubjects=dataset.subsets(ds).subs;
            break
        end
    end
    numSubUse=length(usesubjects);
end

if ~exist('db','var')
    db=matfile([dfold,'fMRI',filesep,cname,filesep,'AllX.mat']);
end

disp('Iterating through subjects...');
for subj = 1:numSubUse % iterate across subjects
    mcfi = usesubjects(subj);
    howmanyruns=ea_cs_dethowmanyruns(dataset,mcfi);

    for s=1:numseed
        for run=1:howmanyruns
            Rw=nan(length(sweightidx{s}),pixdim);

            for ix=1:length(sweightidx{s})
                Rw(ix,:)=db.X(sweightidx{s}(ix),:);
            end
            Rw=mean(Rw,1);
            Rw=Rw/(2^15);
        end

        mmap=dataset.vol.space;
        mmap.fname=[outputfolder,seedfn{s},'_func_',cmd,'_AvgR.nii'];
        mmap.dt=[16,0];
        mmap.img(:)=0;
        mmap.img=single(mmap.img);
        mmap.img(omaskidx)=Rw;
        ea_write_nii(mmap);
        if usegzip
            gzip(mmap.fname);
            delete(mmap.fname);
        end
    end
end
disp('Done.');

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
