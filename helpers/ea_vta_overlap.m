function overlap = ea_vta_overlap(vta, atlas, side)
% Calculate the overlap between VTA and atlases (nifti or xyz coordinates)
%
% Return the overlap in VOXEL (NOT IN MM^3)

% Split left/right side of the atlas
if ~exist('side', 'var')
    side = 'both';
elseif ischar(side)
    side = lower(side);
elseif isnumeric(side)
    if side==1
        side = 'right';
    elseif  side==2
        side = 'left';
    else
        side = 'both';
    end
end

overlap = 0;

% Load VTA image
vtanii = load_nii(vta);
vtanii.img = double(vtanii.img);

% Threshold the efield to avoid leak overlap
efiedthreshold = 200;
if contains(vta, 'efield')
    vtanii.img(vtanii.img<=efiedthreshold)=0;
end

% Check if atlas is nifti file or xyz coordinates
if isfile(atlas)
    atlasnii = load_nii(atlas);
    threshold = max(atlasnii.img(:)) * 0.5;
    atlasnii.img = atlasnii.img > threshold;
    [xvox, yvox, zvox] = ind2sub(size(atlasnii.img), find(atlasnii.img(:)));
    xyz = ea_vox2mm([xvox, yvox, zvox], atlas);
elseif isnumeric(atlas)
    xyz = atlas;
end

% Only calculate for one side, suppose RAS orientation
switch side
    case 'right'
        xyz = xyz(xyz(:,1)>0,:);
    case 'left'
        xyz = xyz(xyz(:,1)<0,:);
end

if ~isempty(xyz)
    % Map XYZ coordinates into VTA image
    vox = round(ea_mm2vox(xyz, vta));
    filter = all(vox>[0,0,0],2) & all(vox<=size(vtanii.img),2); % Remove voxel out of bbox
    if any(filter)
        vox = vox(filter, :);
        ind = unique(sub2ind(size(vtanii.img), vox(:,1), vox(:,2), vox(:,3)));
        % Checking overlap for image1
        overlap = sum(vtanii.img(ind));
    end
end
