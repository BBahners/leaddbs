function fv=ea_electrode2ply(directory,side,handles)

options=ea_handles2options(handles);
options=ea_resolve_elspec(options);
[options.root,options.patientname]=fileparts(directory);
options.root=[options.root,filesep];
options.leadprod='dbs';


[coords_mm,trajectory,markers]=ea_load_reconstruction(options);

elstruct(1).coords_mm=coords_mm;
elstruct(1).coords_mm=ea_resolvecoords(markers,options);
elstruct(1).trajectory=trajectory;
elstruct(1).name=options.patientname;
elstruct(1).markers=markers;
resultfig=figure('visible','off');


pobj.options=options;
pobj.elstruct=elstruct(1);
pobj.showMacro=1;
pobj.side=side;
set(0,'CurrentFigure',resultfig);
el_render(1)=ea_trajectory(pobj);


elrend=el_render.elpatch;

switch side
    case 1
        sidec='right_';
    case 2
        sidec='left_';
end
for f=1:length(elrend)
    fv(f).vertices=get(elrend(f),'Vertices');
    fv(f).faces=get(elrend(f),'Faces');
    fv(f).facevertexcdata=get(elrend(f),'FaceVertexCData');
end
fv=ea_concatfv(fv);
fv=ea_mapcolvert2ind(fv);

ea_patch2ply([directory,'export',filesep,'ply',filesep,sidec,'electrode.ply'],fv.vertices',fv.faces',fv.facevertexcdata');
