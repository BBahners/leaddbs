import qt, vtk, slicer
from qt import QToolBar
import os
from slicer.util import VTKObservationMixin

import WarpDrive
import ImportAtlas
import ImportSubject
from ..Helpers import LeadDBSCall, WarpDriveUtil
from ..Widgets import ToolWidget

class reducedToolbar(QToolBar, VTKObservationMixin):

  def __init__(self):

    QToolBar.__init__(self)
    VTKObservationMixin.__init__(self)

    self.parameterNode = WarpDrive.WarpDriveLogic().getParameterNode()
    self.addObserver(self.parameterNode, vtk.vtkCommand.ModifiedEvent, self.updateToolbarFromParameterNode)
    
    self.setWindowTitle(qt.QObject().tr("LeadDBS"))
    self.name = 'LeadDBS'
  

    #
    # Modality
    #
    self.addWidget(qt.QLabel('Modality:'))
    self.modalityComboBox = qt.QComboBox()
    self.modalityComboBox.addItem('t1')
    self.modalityComboBox.view().pressed.connect(self.onModalityPressed)
    self.addWidget(self.modalityComboBox)

    #
    # B <-> F slider
    #
    self.addSeparator()
    self.addWidget(qt.QLabel('Template:'))
    templateSlider = qt.QSlider(1)
    templateSlider.singleStep = 10
    templateSlider.minimum = 0
    templateSlider.maximum = 100
    templateSlider.value = 0
    templateSlider.setFixedWidth(120)
    templateSlider.connect('valueChanged(int)', lambda value: slicer.util.setSliceViewerLayers(foregroundOpacity = value / 100.0))
    self.addWidget(templateSlider)

    #
    # Segments Opacity
    #
    self.addSeparator()
    self.addWidget(qt.QLabel('Segments:'))
    self.segmentOpacitySlider = qt.QSlider(1)
    self.segmentOpacitySlider.singleStep = 10
    self.segmentOpacitySlider.minimum = 0
    self.segmentOpacitySlider.maximum = 100
    self.segmentOpacitySlider.value = 50
    self.segmentOpacitySlider.setFixedWidth(120)
    self.segmentOpacitySlider.connect('valueChanged(int)', self.onSegmentOpacitySlider)
    self.addWidget(self.segmentOpacitySlider)

    #
    # Space Separator
    #
    self.addSeparator()
    empty = qt.QWidget()
    empty.setSizePolicy(qt.QSizePolicy.Expanding,qt.QSizePolicy.Preferred)
    self.addWidget(empty)

    #
    # Subject
    #

    self.subjectNameLabel = qt.QLabel('Subject: ')    
    self.addWidget(self.subjectNameLabel)

    #
    # Save
    #
    self.saveButton = qt.QPushButton("Finish and Exit")
    self.saveButton.setFixedWidth(200)
    self.saveButton.setStyleSheet("background-color: green")
    self.addWidget(self.saveButton)
    ImportAtlas.ImportAtlasLogic().run(os.path.join(self.parameterNode.GetParameter("MNIAtlasPath"), 'DISTAL Minimal (Ewert 2017)'))
    self.saveButton.connect("clicked(bool)", self.onSaveButton)

    #
    # Update
    #

    self.updateModalities(self.parameterNode.GetParameter("subjectPath"))
    self.initSubject()
    self.onModalityPressed([],self.modalityComboBox.currentText)
    self.updateToolbarFromParameterNode()


  def onSegmentOpacitySlider(self, value):
    segmentsFolderNode = self.parameterNode.GetNodeReference("Segmentation")
    if segmentsFolderNode:
      segmentsFolderNode.SetOpacity(value/100)

  def initSubject(self):
    # set up transform
    inputNode = LeadDBSCall.loadSubjectTransform(self.parameterNode.GetParameter("subjectPath"), self.parameterNode.GetParameter("antsApplyTransformsPath"))
    outputNode = slicer.mrmlScene.AddNewNodeByClass('vtkMRMLGridTransformNode')
    inputNode.SetAndObserveTransformNodeID(outputNode.GetID())
    # set up segmentation
    segmentsFolderNode = ImportSubject.ImportSubjectLogic().importSegmentations(self.parameterNode.GetParameter("subjectPath"))
    if segmentsFolderNode:
      shnode = slicer.mrmlScene.GetSubjectHierarchyNode()
      IDList = vtk.vtkIdList()
      shnode.GetItemChildren(shnode.GetItemByDataNode(segmentsFolderNode), IDList)
      for i in range(IDList.GetNumberOfIds()):
        shnode.GetItemDataNode(IDList.GetId(i)).SetAndObserveTransformNodeID(self.parameterNode.GetNodeReferenceID("InputNode"))    
        shnode.GetItemDataNode(IDList.GetId(i)).GetDisplayNode().SetVisibility2D(1)   
        shnode.GetItemDataNode(IDList.GetId(i)).GetDisplayNode().SetVisibility3D(0)   
      segmentsFolderNode.SetOpacity(self.segmentOpacitySlider.value/100)
    # parameter node
    self.parameterNode.SetNodeReferenceID("InputNode", inputNode.GetID())
    self.parameterNode.SetNodeReferenceID("OutputGridTransform", outputNode.GetID())
    self.parameterNode.SetNodeReferenceID("Segmentation", segmentsFolderNode.GetID() if segmentsFolderNode else None)


  def onModalityPressed(self, item, modality=None):
    if modality is None:
      modality = self.modalityComboBox.itemText(item.row())
    # find old nodes and delete
    slicer.mrmlScene.RemoveNode(self.parameterNode.GetNodeReference("ImageNode"))
    slicer.mrmlScene.RemoveNode(self.parameterNode.GetNodeReference("TemplateNode"))
    # initialize new image and init
    imageNode = ImportSubject.ImportSubjectLogic().importImage(self.parameterNode.GetParameter("subjectPath"), modality)
    imageNode.SetAndObserveTransformNodeID(self.parameterNode.GetNodeReferenceID("InputNode"))    
    # change to t1 in case modality not present
    modality = modality if modality in ['t1','t2','pca','pd'] else 't1'
    templateNode = slicer.util.loadVolume(os.path.join(self.parameterNode.GetParameter("MNIPath"), modality + ".nii"), properties={'show':False})
    templateNode.GetDisplayNode().AutoWindowLevelOff()
    templateNode.GetDisplayNode().SetWindow(100)
    templateNode.GetDisplayNode().SetLevel(70)
    # set view
    slicer.util.setSliceViewerLayers(background=imageNode.GetID(), foreground=templateNode.GetID())
    # set parameter
    self.parameterNode.SetParameter("modality", modality)
    self.parameterNode.SetNodeReferenceID("ImageNode", imageNode.GetID())
    self.parameterNode.SetNodeReferenceID("TemplateNode", templateNode.GetID())


  def updateToolbarFromParameterNode(self, caller=None, event=None):
    # subject text
    subjectN = int(self.parameterNode.GetParameter("subjectN"))
    subjectPaths = self.parameterNode.GetParameter("subjectPaths").split(self.parameterNode.GetParameter("separator"))
    self.subjectNameLabel.text = 'Subject: ' + os.path.split(os.path.abspath(self.parameterNode.GetParameter("subjectPath")))[-1]
    self.saveButton.text = 'Finish and Exit' if subjectN == len(subjectPaths)-1 else 'Finish and Next'
    # modality
    self.modalityComboBox.setCurrentText(self.parameterNode.GetParameter("modality"))


  def onSaveButton(self):
    ToolWidget.AbstractToolWidget.cleanEffects()
    subjectPath = self.parameterNode.GetParameter("subjectPath")

    if WarpDriveUtil.getPointsFromAttribute('source').GetNumberOfPoints(): # corrections made
      LeadDBSCall.applyChanges(subjectPath, self.parameterNode.GetNodeReference("InputNode"), self.parameterNode.GetNodeReference("ImageNode")) # save changes
    else:
      if not LeadDBSCall.queryUserApproveSubject(subjectPath):
        return # user canceled 

    # clean up

    # remove nodes
    slicer.mrmlScene.RemoveNode(self.parameterNode.GetNodeReference("InputNode"))
    slicer.mrmlScene.RemoveNode(self.parameterNode.GetNodeReference("ImageNode"))
    slicer.mrmlScene.RemoveNode(self.parameterNode.GetNodeReference("OutputGridTransform"))
    LeadDBSCall.removeNodeAndChildren(self.parameterNode.GetNodeReference("Segmentation"))
    
    LeadDBSCall.DeleteCorrections()

    # move to next subject

    nextSubjectN = int(self.parameterNode.GetParameter("subjectN"))+1
    subjectPaths = self.parameterNode.GetParameter("subjectPaths").split(self.parameterNode.GetParameter("separator"))
  
    if nextSubjectN < len(subjectPaths):
      self.updateModalities(subjectPaths[nextSubjectN])
      self.parameterNode.SetParameter("subjectN", str(nextSubjectN))
      self.parameterNode.SetParameter("subjectPath", subjectPaths[nextSubjectN])
      self.initSubject()
      self.onModalityPressed([],self.parameterNode.GetParameter("modality"))
      self.updateToolbarFromParameterNode()
    else:
      slicer.util.exit()


  def updateModalities(self, subjectPath):
    currentModality = self.modalityComboBox.currentText
    subjectModalities = ImportSubject.ImportSubjectLogic().getAvailableModalities(subjectPath)
    if currentModality not in subjectModalities:
      self.parameterNode.SetParameter("modality", subjectModalities[0])
    self.modalityComboBox.clear()
    self.modalityComboBox.addItems(subjectModalities)

