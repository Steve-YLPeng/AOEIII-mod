-- grnreaderX Import Script for 3ds Max
--
-- Copyright (c) 2016 Cliff Kang
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in
-- all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
--
--

-- import structure definitions

struct gmodel (
	name,
	skeleton,
	meshes
)

struct gskeleton (
	bones
)

struct gbone (
	name,
	parent_index,
	transform
)

struct gmesh (
	name,
	vertices,
	bones,
	material_indices,
	face_groups
)

struct gvertex (
	position,
	normal,
	uv,
	bone_indices,
	weights
)

struct gface_group (
	mat_id,
	faces
)

struct gmaterial (
	name,
	diffuse_id,
	opacity_id,
	bump_id
)

struct ganimation (
	frame_count,
	fps,
	controller_groups
)

struct gcontroller_group (
	name,
	controllers
)

struct gcontroller (
	name,
	position_keys,
	rotation_keys,
	scale_keys
)

struct gkey (
	frame,
	value
)

-- global variables
gx_title = "grnreaderX"
if gx_reselect_textures == undefined then gx_reselect_textures = false
if gx_bone_size == undefined then gx_bone_size = [0.05, 0.05]
if gx_slider_time == undefined then gx_slider_time = false
gx_plugin_mode = doesFileExist ((getDir #startupScripts) + "\\grnreaderX.ms")

struct gimporter (
	-- import data
	textures,
	materials,
	models,
	animations,
	
	scene_textures,
	scene_materials,
	scene_skeletons,
	
	imp_mat_id,
	imp_mat,
	imp_model_id,
	imp_model,
	imp_mesh_id,
	imp_mesh,
	imp_vertex_id,
	imp_vertex,
	imp_face_group_id,
	imp_faces,
	imp_face_id,
	imp_anim_id,
	imp_anim,
	imp_ctrl_group_id,
	imp_ctrl_group,
	imp_ctrl_id,
	imp_ctrl,
	
	-- utility functions
	fn find_bone name objs =
	(
		local result
		for b in objs where (classof b == BoneGeometry or classof b == Point or classof b == Biped_Object or classof b == Dummy) and stricmp b.name name == 0 do result = b
		result
	),
	
	-- scene creation functions
	
	fn create_texture t = (
		bitmaptexture filename:t
	),
	
	fn create_material m = (
		local result = StandardMaterial()
		result.name = m.name
		if m.diffuse_id != undefined then result.diffuseMap = scene_textures[m.diffuse_id]
		if m.opacity_id != undefined then result.opacityMap = scene_textures[m.opacity_id]
		if m.bump_id != undefined then result.bumpMap = scene_textures[m.bump_id]
		result
	),
	
	fn create_bone b si = (
		local result
		local bone_zaxis = [0, 1, 0]
		
		if b.parent_index == 0 then result = BoneSys.createBone b.transform.pos b.transform.pos bone_zaxis
		else result = BoneSys.createBone b.transform.pos scene_skeletons[si].bones[b.parent_index].transform.pos bone_zaxis
		
		result.name = b.name
		
		-- fix bone transform
		local offset_transform = (scaleMatrix result.objectOffsetScale) * (result.objectOffsetRot as matrix3) * (transMatrix result.objectOffsetPos)
		offset_transform *= result.transform * (inverse b.transform)
		result.transform = b.transform
		result.objectOffsetPos = offset_transform.translation
		result.objectOffsetRot = offset_transform.rotation
		result.objectOffsetScale = offset_transform.scale
		
		--fix negative scale
		if result.scale[1] < -0.999999 and result.scale[2] < -0.999999 and result.scale[3] < -0.999999 then result.objectOffsetScale = [-1, -1, -1]
		
		result.width = gx_bone_size.x
		result.height = gx_bone_size.y
		
		if b.parent_index > 0 then result.parent = scene_skeletons[si].bones[b.parent_index]
		result
	),
	
	fn create_mesh m si = (
		local face_count = 0
		for g in m.face_groups do face_count = face_count + g.faces.count
		
		local result = mesh name:m.name numverts:m.vertices.count numfaces:face_count
		setNumTVerts result m.vertices.count
		buildTVFaces result
		for i = 1 to m.vertices.count do 
		(
			local vertex = m.vertices[i]
			setVert result i vertex.position
			setNormal result i vertex.normal
			setTVert result i vertex.uv[1] vertex.uv[2] 0
		)
		
		local parent_material = multiMaterial numSubs: m.material_indices.count
		for i = 1 to m.material_indices.count do parent_material[i] = scene_materials[m.material_indices[i]]
		result.material = parent_material
			
		local face_index = 1
		for g in m.face_groups do
		( 
			for face in g.faces do
			(
				setFace result face_index face
				setFaceMatID result face_index g.mat_id
				face_index += 1
			)
		)
		
		for i = 1 to result.numFaces do setTVFace result i (getface result i)
		
		Select result
		max modify mode	
		
		local mod_edit_normals = Edit_Normals()
		addModifier result mod_edit_normals
		for f = 1 to getNumFaces result do
		(
			local face = getFace result f
			for i = 1 to 3 do
			(
				local normal_id = mod_edit_normals.getNormalID f i
				mod_edit_normals.setNormal normal_id m.vertices[face[i]].normal
				mod_edit_normals.setNormalExplicit normal_id explicit:true
			)
		)
		
		local mod_skin = Skin()
		addModifier result mod_skin
		
		for b in m.bones do skinOps.addBone mod_skin (find_bone b scene_skeletons[si].bones) 1
		
		disableSceneRedraw()
		
		if m.vertices[1].weights != undefined then
		(
			for i = 1 to result.numVerts do
			(
				local vertex_weights = m.vertices[i].weights
				local bone_indices = m.vertices[i].bone_indices
				if vertex_weights[1] == 1 then
				(
					skinOps.ReplaceVertexWeights mod_skin i bone_indices[1] 1.0
				)
				else
				(
					local indices = #()
					local weights = #()
					for w = 1 to 4 do
					(
						if vertex_weights[w] > 0 then
						(
							append indices bone_indices[w]
							append weights vertex_weights[w]
						)
					)
					
					skinOps.ReplaceVertexWeights mod_skin i indices weights
				)
			)
		)
		enableSceneRedraw()
		result
	),	
	
	fn create_model i = (
		local model = models[i]
		local result
		local objs = #()
		
		scene_skeletons[i] = gskeleton #()
		for b in model.skeleton.bones do
		(
			local scene_bone = create_bone b i
			append scene_skeletons[i].bones scene_bone
			append objs scene_bone
			
		)
		
		for m in model.meshes do append objs (create_mesh m i)
		
		result = group objs
		result.name = model.name
	),
	
	fn create_animation a = (
		local start = 0f
		local end = a.frame_count as time
		frameRate = a.fps
		if gx_slider_time then
		(
			start = sliderTime
			end += sliderTime
		)
		animationRange = interval 0f end
		for g in a.controller_groups do
		(
			local objs = objects
			local msg
			for m = 1 to models.count do 
			(
				if stricmp g.name models[m].name == 0 then objs = scene_skeletons[m].bones
			)
			for c in g.controllers do
			(
				local b = find_bone c.name objs
				if b != undefined then
				(
					if c.position_keys.count > 0 then
					(
						local pos_ctrl = bezier_position()
						b.pos.controller = pos_ctrl
						
						for k in c.position_keys do
						(
							local pos_key = addNewKey pos_ctrl (start + k.frame)
							pos_key.inTangentType = #slow
							pos_key.outTangentType = #slow
							pos_key.value = k.value
						)
					)
					
					if c.rotation_keys.count > 0 then
					(
						local rot_ctrl = bezier_rotation()
						b.rotation.controller = rot_ctrl
						
						for k in c.rotation_keys do
						(
							local rot_key = addNewKey rot_ctrl (start + k.frame)
							rot_key.value = k.value
						)
					)

					if c.scale_keys.count > 0 then
					(
						local scale_ctrl = bezier_scale()
						b.scale.controller = scale_ctrl
						
						for k in c.scale_keys do
						(
							local scale_key = addNewKey scale_ctrl (start + k.frame)
							scale_key.inTangentType = #slow
							scale_key.outTangentType = #slow					
							scale_key.value = k.value
						)
					)
				)
				else
				(
					if msg == undefined then msg = "create_animation error - the following bones in controller group '" + g.name + "' cannot be found:\n\n"
					msg += c.name
					msg += "\n"
				)
			)
			if msg != undefined then messageBox msg title:gx_title
		)
	),

	fn clean_up = (
		textures = #()
		materials = #()
		models = #()
		animations = #()
		
		scene_textures = #()
		scene_materials = #()
		scene_skeletons = #()
		
		imp_mat_id = 0
		imp_model_id = 0
		imp_anim_id = 0
		
		imp_mat = undefined
		imp_model = undefined
		imp_mesh = undefined
		imp_vertex = undefined
		imp_faces = undefined
		imp_anim = undefined
		imp_ctrl_group = undefined
		imp_ctrl = undefined
	),
	
	fn init = (
		clean_up()
	),
	
	fn import = (	
		try
		(
			local group_objs = #()
			local ver = maxVersion()
			
			-- use slate material editor if available
			local sme_avl = ver[1] >= 13000
			
			if gx_reselect_textures then
			(
				for t = 1 to textures.count do
				(
					local file = getOpenFileName filename:textures[t] types:"Targa image file(*.tga)|*.tga|Adobe psd reader(*.psd)|*.psd|"
					if file != undefined then textures[t] = file
				)
			)
			
			for t in textures do append scene_textures (create_texture t)
			
			if materials.count > 0 then
			(
				if not sme_avl then
				(
					local msg		
					local mat_id = 0
					local meditmat_id = 1
					for i = 1 to materials.count do
					(
						append scene_materials (create_material materials[i])
						local imported = false
						for m = meditmat_id to 24 do
						(
							if not imported then
							(
								if classof meditmaterials[m] == StandardMaterial then
								(
									if meditmaterials[m].diffuseMap == undefined and meditmaterials[m].opacityMap == undefined and meditmaterials[m].bumpMap == undefined then
									(
										mat_id += 1
										meditmaterials[m] = scene_materials[mat_id]
										meditmaterials[m].showInViewport = on
										scene_materials[mat_id] = meditmaterials[m]
										mmeditmat_id = m + 1
										imported = true
									)
								)
							)
						)
						if not imported then
						(
							if msg == undefined then msg = "import warning - the following materials cannot be imported because there are no remaining slots available in Material Editor:\n\n"
							msg += materials[i].name
							msg += "\n"
						)
					)
					if msg != undefined then messageBox msg title:gx_title 
				)
				else
				(
					local view_name
					local model_name = ""
					local sme_view
					local view_id = 1
					
					if models.count > 0 then model_name = " - " + models[1].name
					
					sme.Open()
					view_name = "View" + (view_id as string) + model_name
					while sme.GetViewByName view_name > 0 do
					(
						view_id += 1
						view_name = "View" + (view_id as string) + model_name
					)
					
					sme_view = sme.GetView (sme.CreateView view_name)
					for i = 1 to materials.count do 
					(
						append scene_materials (create_material materials[i])
						sme_view.createNode scene_materials[i] [0, 300 * (i - 1)]
						scene_materials[i].showInViewport = on
					)
					sme.Close()
				)
			)
			
			for i = 1 to models.count do create_model i
			
			for a in animations do create_animation a

			clean_up()
		)
		catch
		(
			messageBox "import failed - script file is corrupted." title:gx_title
		)
	)
	
)

--- importer initialization ---
gx_importer = gimporter()
gx_importer.init()

-- file import function definitions

-- texture
fn t name = (
	append gx_importer.textures name
)

-- material
fn mat name = (
	gx_importer.imp_mat_id += 1
	append gx_importer.materials (gmaterial name)
	gx_importer.imp_mat = gx_importer.materials[gx_importer.imp_mat_id]
)

-- diffuse texture
fn td id = (
	gx_importer.imp_mat.diffuse_id = id
)

-- opacity texture
fn tp id = (
	gx_importer.imp_mat.opacity_id = id
)

-- bump texture
fn tb id = (
	gx_importer.imp_mat.bump_id = id
)

-- model
fn md name = (
	gx_importer.imp_model_id += 1
	append gx_importer.models (gmodel name (gskeleton #()) #())
	gx_importer.imp_model = gx_importer.models[gx_importer.imp_model_id]
	gx_importer.imp_mesh_id = 0
)

-- bone
fn b name parent_index tm1 tm2 tm3 tm4 tm5 tm6 tm7 tm8 tm9 tm10 tm11 tm12 = (
	append gx_importer.imp_model.skeleton.bones (gbone name parent_index (matrix3 [tm1, tm2, tm3] [tm4, tm5, tm6] [tm7, tm8, tm9] [tm10, tm11, tm12]))
)

-- mesh
fn m name = (
	gx_importer.imp_mesh_id += 1
	append gx_importer.imp_model.meshes (gmesh name #() #() #() #())
	gx_importer.imp_mesh = gx_importer.imp_model.meshes[gx_importer.imp_mesh_id]
	gx_importer.imp_vertex_id = 0
	gx_importer.imp_face_group_id = 0
)

-- mesh bone
fn mb name = (
	append gx_importer.imp_mesh.bones name
)

-- mesh material 
fn mm i = (
	append gx_importer.imp_mesh.material_indices i
)

-- vertex position
fn v x y z = (
	gx_importer.imp_vertex_id += 1
	append gx_importer.imp_mesh.vertices (gvertex [x,y,z])
	gx_importer.imp_vertex = gx_importer.imp_mesh.vertices[gx_importer.imp_vertex_id]
)

-- vertex normal
fn vn x y z = (
	gx_importer.imp_vertex.normal = [x,y,z]
)

-- vertex uv
fn vt x y = (
	gx_importer.imp_vertex.uv = [x,y]
)

-- vertex weights
fn vw w1 w2 w3 w4 i1 i2 i3 i4 = (
	gx_importer.imp_vertex.weights = #(w1, w2, w3, w4)
	gx_importer.imp_vertex.bone_indices = #(i1, i2, i3, i4)
)

-- face group
fn fg i = (
	gx_importer.imp_face_group_id += 1
	append gx_importer.imp_mesh.face_groups (gface_group i #())
	gx_importer.imp_faces = gx_importer.imp_mesh.face_groups[gx_importer.imp_face_group_id].faces
)

-- face
fn f i1 i2 i3 = (
	append gx_importer.imp_faces [i1, i2, i3]
)

-- animation
fn a frame_count fps = (
	gx_importer.imp_anim_id += 1
	append gx_importer.animations (ganimation frame_count fps #())
	gx_importer.imp_anim = gx_importer.animations[gx_importer.imp_anim_id]
	gx_importer.imp_ctrl_group_id = 0
)

-- controller group
fn cg name = (
	gx_importer.imp_ctrl_group_id += 1
	append gx_importer.imp_anim.controller_groups (gcontroller_group name #())
	gx_importer.imp_ctrl_group = gx_importer.imp_anim.controller_groups[gx_importer.imp_ctrl_group_id]
	gx_importer.imp_ctrl_id = 0
)

-- controller
fn c name = (
	gx_importer.imp_ctrl_id += 1
	append gx_importer.imp_ctrl_group.controllers (gcontroller name #() #() #())
	gx_importer.imp_ctrl = gx_importer.imp_ctrl_group.controllers[gx_importer.imp_ctrl_id]
)

-- key position
fn kp i x y z = (
	append gx_importer.imp_ctrl.position_keys (gkey i [x,y,z])
)

-- key rotation
fn kr i x y z w = (
	append gx_importer.imp_ctrl.rotation_keys (gkey i (quat x y z w))
)

-- key scale
fn ks i x y z = (
	append gx_importer.imp_ctrl.scale_keys (gkey i [x,y,z])
)

-- importer utility
utility gx_importer_utility "grnreaderX"
(
	local exe = getINISetting ((getDir #plugcfg) + "\\grnreaderX.ini") "grnreaderX" "path"
	
	rollout gx_importer_ui "grnreaderX"
	(
		checkbox cb_reselect_textures "Re-select textures" checked:gx_reselect_textures
		spinner s_bone_width "Bone Width:" range:[gx_bone_size.x, 10000, 0.01] align:#left
		spinner s_bone_height "Bone Height:" range:[gx_bone_size.y, 10000, 0.01] align:#left
		checkbox cb_slider_time "Start from slider" checked:gx_slider_time
		local files = #()
		local items = #()
		group "Files:"
		(
			listbox lb_files ""
			button btn_add "Add" width:60 across:2
			button btn_remove "Remove" width:60
		)
		button btn_import "Import" width:60
		button btn_setup "Setup" width:60
		
		on cb_reselect_textures changed stat do gx_reselect_textures = stat
		
		on s_bone_width changed val do gx_bone_size.x = val
		
		on s_bone_height changed val do gx_bone_size.y = val
		
		on cb_slider_time changed stat do gx_slider_time = stat
		
		on btn_add pressed do
		(
			local file = getOpenFileName types:"Granny Runtime 2 File (*.gr2)|*.gr2|"
			if file != undefined then
			(
				append files file
				append items (filenameFromPath file)
				lb_files.items = items
				lb_files.selection = items.count
			)
		)
		
		on btn_remove pressed do
		(
			if lb_files.selection > 0 then
			(
				local i = lb_files.selection
				deleteItem files i
				deleteItem items i
				lb_files.items = items
			)
		)
		
		on btn_import pressed do
		(
			if files.count > 0 then
			(
				local command = "\" \"" + exe + "\" \"-d\""
				local ver = maxVersion()
				local ret
				
				for f in files do command += " \"" + f + "\""
				command += " \""
				
				if ver[1] >= 12000 then HiddenDOSCommand command ExitCode:&ret
				else ret = DOSCommand command
				
				if ret == 0 then
				(
					local script = (getFilenamePath files[1]) + (getFilenameFile files[1]) + ".ms"
					try
					(
						filein script
					)
					catch
					(
						messageBox "import failed: script file corrupted." title:gx_title
					)
					deleteFile script
					gx_importer.import()
		
					files = #()
					items = #()
					lb_files.items = #()
				)
				else messageBox "import failed: cannot execute external command." title:gx_title
			)
		)
		
		on btn_setup pressed do
		(
			local file = getOpenFileName caption:"Locate 'grnreaderX.exe'" types:"Executeable file(*.exe)|*.exe|"
			if file != undefined then
			(
				if not (setINISetting ((getDir #plugcfg) + "\\grnreaderX.ini") "grnreaderX" "path" file) then
				(
					messageBox "plugin setup: unable to save plugin settings." title:gx_title
				)
				else exe = file
			)			
		)
	)
	
	on gx_importer_utility open do
	(
		if gx_plugin_mode then addRollout gx_importer_ui
	)
	
	on gx_importer_utility close do
	(
		if gx_plugin_mode then removeRollout gx_importer_ui
	)
)

--- treb_skeleton.GR2 ---
t "C:\Program Files (x86)\Microsoft Games\Test\art\units\KnB\Trebuchet\trebuchet.tga"
mat "01 - Default"
td 1
md "Bone05"
b "Bone05" 0 1 0 3.57628e-07 0 1 0 -3.57628e-07 0 1 -0.289186 -17.5861 -0.0847797
b "Bone25" 1 -0.00699646 0.0067855 0.00223755 -0.00696202 -0.00717846 -2.31934e-09 0.00160622 -0.00155779 0.00974645 1.76489 -18.1277 0.710406
b "Bone26" 2 -0.000288532 0.00868934 9.22753e-05 -0.000287112 -0.00919256 1.52283e-09 6.62399e-05 -0.00199487 0.000401942 1.76864 -18.1011 0.71023
b "Bone04" 1 0.00699645 -0.0067855 0.00223756 0.00696202 0.00717846 2.80762e-09 -0.00160622 0.00155779 0.00974645 1.76489 -18.1277 -0.879965
b "Bone24" 4 0.00699645 -0.00678562 0.00223758 0.00696201 0.00717839 1.22071e-08 -0.00160621 0.00155774 0.00974646 1.85595 -18.1069 -0.875668
b "Bone12" 1 0.999961 0.00881089 3.56343e-07 -0.00881089 0.999961 7.94302e-09 -3.56259e-07 -1.10824e-08 1 0.235227 -21.5145 0.814732
b "Bone13" 1 -8.06768e-09 -0.845489 0.533994 7.90251e-07 -0.533994 -0.845489 1 4.47035e-07 5.82517e-07 0.145985 -22.4298 1.79022
b "Bone11" 7 -6.18749e-07 0.00537644 0.999986 4.76351e-07 -0.999986 0.00537644 1 4.79631e-07 5.61359e-07 0.427828 -23.9078 1.50452
b "Bone10" 1 0.999961 0.00881089 3.56343e-07 -0.00881089 0.999961 7.94302e-09 -3.56259e-07 -1.10824e-08 1 0.235228 -21.5145 -0.98429
b "Bone08" 1 4.6045e-07 -0.845489 -0.533994 1.69448e-07 -0.533994 0.845489 -1 -5.06639e-07 -1.30134e-07 0.145987 -22.4298 -1.95978
b "Bone07" 10 5.51928e-08 0.00537659 -0.999986 4.83267e-07 -0.999986 -0.00537659 -1 -4.82891e-07 -1.13394e-07 -0.135854 -23.9078 -1.67408
b "Bone06" 1 1 8.38072e-09 3.62016e-07 -8.38072e-09 1 2.36159e-09 -3.62016e-07 -2.36159e-09 1 1.58581 -18.3673 -0.0847791
b "Bone01" 1 0.999997 -0.00248909 3.57635e-07 0.00248909 0.999997 8.87565e-10 -3.57636e-07 2.62623e-12 1 7.36706 -14.9298 -0.084777
b "Bone03" 13 -0.999999 0.00115452 -3.57636e-07 -0.00115452 -0.999999 -4.10271e-10 -3.57636e-07 2.62623e-12 1 5.80412 -14.9299 -0.0847775
b "Dummy01" 13 2.61304e-09 -8.2318e-10 1 0.00248909 0.999997 9.31323e-10 -0.999997 0.00248909 2.61509e-09 10.8338 -15.9842 -0.0847759
b "Bone32" 15 -0.277421 -0.960748 2.88933e-07 0.960748 -0.277421 4.42041e-07 -3.44534e-07 4.00224e-07 1 10.8079 -15.848 -0.0847758
b "Bone09" 13 -0.877738 -0.479142 -3.1391e-07 0.479142 -0.877738 1.71361e-07 -3.57637e-07 2.6148e-12 1 19.2652 -14.8971 -0.0847732
b "Bone14" 17 -0.999854 0.0171124 -3.57584e-07 -0.0171124 -0.999854 -6.11741e-09 -3.57637e-07 2.62146e-12 1 18.5219 -15.3029 -0.0847735
b "Bone15" 18 -1 0.00020828 -3.57637e-07 -0.00020828 -1 -7.18664e-11 -3.57637e-07 2.62217e-12 1 17.8243 -15.2909 -0.0847737
b "Bone16" 19 -0.996809 -0.0798227 -3.56495e-07 0.0798227 -0.996809 2.85501e-08 -3.57637e-07 2.61835e-12 1 16.706 -15.2907 -0.0847742
b "Bone17" 20 -0.992714 -0.1205 -3.5503e-07 0.1205 -0.992714 4.30979e-08 -3.57637e-07 2.6219e-12 1 15.6232 -15.3774 -0.0847745
b "Bone18" 21 -0.993602 -0.112935 -3.55348e-07 0.112935 -0.993602 4.03924e-08 -3.57637e-07 2.61835e-12 1 14.4817 -15.516 -0.084775
b "Bone19" 22 -0.994722 -0.102607 -3.55749e-07 0.102607 -0.994722 3.66986e-08 -3.57637e-07 2.61835e-12 1 13.3253 -15.6474 -0.0847754
b "Bone20" 23 -0.983866 -0.178907 -3.51866e-07 0.178907 -0.983866 6.39864e-08 -3.57637e-07 2.6148e-12 1 12.1608 -15.7675 -0.0847758
b "Bone21" 24 -0.976201 -0.216867 -3.49125e-07 0.216867 -0.976201 7.75621e-08 -3.57637e-07 2.62901e-12 1 11.0498 -15.9695 -0.0847762
b "Bone22" 25 -0.935155 -0.354239 -3.34445e-07 0.354239 -0.935155 1.26691e-07 -3.57637e-07 2.60059e-12 1 9.98122 -16.2069 -0.0847765
m "Bone05"
v -0.281373 -17.5939 -0.0769672
vn 18.3902 0 61.3009
vt 0 1
v -0.281373 -17.5783 -0.0769672
vn 18.3903 61.3009 6.57687e-06
vt 0 1
v -0.281373 -17.5783 -0.0925922
vn 18.3903 61.3009 6.57687e-06
vt 0 1
v -0.281373 -17.5939 -0.0925922
vn 18.3903 0 -61.3009
vt 0 1
v -0.257936 -17.5869 -0.0839985
vn 64 0 2.28882e-05
vt 0 1
v -0.257936 -17.5853 -0.0839985
vn 64 0 2.28882e-05
vt 0 1
v -0.257936 -17.5853 -0.085561
vn 64 0 2.28882e-05
vt 0 1
v -0.257936 -17.5869 -0.085561
vn 64 0 2.28882e-05
vt 0 1
v -0.289186 -17.5861 -0.0847797
vn -45.2548 0 45.2548
vt 0 1
v -0.257936 -17.5853 -0.0839985
vn 18.3903 61.3009 6.57687e-06
vt 0 1
v -0.257936 -17.5853 -0.085561
vn 18.3903 61.3009 6.57687e-06
vt 0 1
v -0.257936 -17.5869 -0.0839985
vn 18.3902 0 61.3009
vt 0 1
v -0.281373 -17.5783 -0.0769672
vn 18.3902 0 61.3009
vt 0 1
v -0.257936 -17.5853 -0.0839985
vn 18.3902 0 61.3009
vt 0 1
v -0.257936 -17.5869 -0.085561
vn 18.3903 0 -61.3009
vt 0 1
v -0.257936 -17.5853 -0.085561
vn 18.3903 0 -61.3009
vt 0 1
v -0.281373 -17.5783 -0.0925922
vn 18.3903 0 -61.3009
vt 0 1
v -0.257936 -17.5869 -0.0839985
vn 18.3903 -61.3009 6.57687e-06
vt 0 1
v -0.281373 -17.5939 -0.0769672
vn 18.3903 -61.3009 6.57687e-06
vt 0 1
v -0.257936 -17.5869 -0.085561
vn 18.3903 -61.3009 6.57687e-06
vt 0 1
v -0.281373 -17.5939 -0.0925922
vn 18.3903 -61.3009 6.57687e-06
vt 0 1
v -0.281373 -17.5939 -0.0769672
vn -45.2548 0 45.2548
vt 0 1
v -0.281373 -17.5783 -0.0769672
vn -45.2548 0 45.2548
vt 0 1
v -0.289186 -17.5861 -0.0847797
vn -45.2548 45.2548 -1.61844e-05
vt 0 1
v -0.281373 -17.5783 -0.0769672
vn -45.2548 45.2548 -1.61844e-05
vt 0 1
v -0.281373 -17.5783 -0.0925922
vn -45.2548 45.2548 -1.61844e-05
vt 0 1
v -0.289186 -17.5861 -0.0847797
vn -45.2548 0 -45.2548
vt 0 1
v -0.281373 -17.5783 -0.0925922
vn -45.2548 0 -45.2548
vt 0 1
v -0.281373 -17.5939 -0.0925922
vn -45.2548 0 -45.2548
vt 0 1
v -0.289186 -17.5861 -0.0847797
vn -45.2548 -45.2548 -1.61844e-05
vt 0 1
v -0.281373 -17.5939 -0.0925922
vn -45.2548 -45.2548 -1.61844e-05
vt 0 1
v -0.281373 -17.5939 -0.0769672
vn -45.2548 -45.2548 -1.61844e-05
vt 0 1
fg 1
f 30 31 32
f 27 28 29
f 24 25 26
f 9 22 23
f 21 20 19
f 18 19 20
f 17 16 4
f 15 4 16
f 14 13 12
f 1 12 13
f 11 3 10
f 2 10 3
f 7 6 8
f 5 8 6
mb "Bone05"
m "Bone01"
v 7.37486 -14.9377 -0.0769645
vn 0.0979377 -0.000243777 63.9999
vt 0 1
v 7.3749 -14.922 -0.0769645
vn 0.257276 63.9995 1.27524e-07
vt 0 1
v 7.3749 -14.922 -0.0925895
vn 0.257276 63.9995 1.27524e-07
vt 0 1
v 7.37486 -14.9377 -0.0925895
vn 0.0979835 -0.000243848 -63.9999
vt 0 1
v 11.9685 -14.9421 -0.0839941
vn 63.9998 -0.159288 2.2902e-05
vt 0 1
v 11.9685 -14.9405 -0.0839941
vn 63.9998 -0.159288 2.2902e-05
vt 0 1
v 11.9685 -14.9405 -0.0855566
vn 63.9998 -0.159288 2.2902e-05
vt 0 1
v 11.9685 -14.9421 -0.0855566
vn 63.9998 -0.159288 2.2902e-05
vt 0 1
v 7.36706 -14.9298 -0.084777
vn -45.2547 0.112634 45.2548
vt 0 1
v 11.9685 -14.9405 -0.0839941
vn 0.257276 63.9995 1.27524e-07
vt 0 1
v 11.9685 -14.9405 -0.0855566
vn 0.257276 63.9995 1.27524e-07
vt 0 1
v 11.9685 -14.9421 -0.0839941
vn 0.0979377 -0.000243777 63.9999
vt 0 1
v 7.3749 -14.922 -0.0769645
vn 0.0979377 -0.000243777 63.9999
vt 0 1
v 11.9685 -14.9405 -0.0839941
vn 0.0979377 -0.000243777 63.9999
vt 0 1
v 11.9685 -14.9421 -0.0855566
vn 0.0979835 -0.000243848 -63.9999
vt 0 1
v 11.9685 -14.9405 -0.0855566
vn 0.0979835 -0.000243848 -63.9999
vt 0 1
v 7.3749 -14.922 -0.0925895
vn 0.0979835 -0.000243848 -63.9999
vt 0 1
v 11.9685 -14.9421 -0.0839941
vn -0.0613553 -64 -5.74143e-08
vt 0 1
v 7.37486 -14.9377 -0.0769645
vn -0.0613553 -64 -5.74143e-08
vt 0 1
v 11.9685 -14.9421 -0.0855566
vn -0.0613553 -64 -5.74143e-08
vt 0 1
v 7.37486 -14.9377 -0.0925895
vn -0.0613553 -64 -5.74143e-08
vt 0 1
v 7.37486 -14.9377 -0.0769645
vn -45.2547 0.112634 45.2548
vt 0 1
v 7.3749 -14.922 -0.0769645
vn -45.2547 0.112634 45.2548
vt 0 1
v 7.36706 -14.9298 -0.084777
vn -45.1421 45.3673 -1.61288e-05
vt 0 1
v 7.3749 -14.922 -0.0769645
vn -45.1421 45.3673 -1.61288e-05
vt 0 1
v 7.3749 -14.922 -0.0925895
vn -45.1421 45.3673 -1.61288e-05
vt 0 1
v 7.36706 -14.9298 -0.084777
vn -45.2547 0.112634 -45.2548
vt 0 1
v 7.3749 -14.922 -0.0925895
vn -45.2547 0.112634 -45.2548
vt 0 1
v 7.37486 -14.9377 -0.0925895
vn -45.2547 0.112634 -45.2548
vt 0 1
v 7.36706 -14.9298 -0.084777
vn -45.3673 -45.142 -1.62595e-05
vt 0 1
v 7.37486 -14.9377 -0.0925895
vn -45.3673 -45.142 -1.62595e-05
vt 0 1
v 7.37486 -14.9377 -0.0769645
vn -45.3673 -45.142 -1.62595e-05
vt 0 1
fg 1
f 30 31 32
f 27 28 29
f 24 25 26
f 9 22 23
f 21 20 19
f 18 19 20
f 17 16 4
f 15 4 16
f 14 13 12
f 1 12 13
f 11 3 10
f 2 10 3
f 7 6 8
f 5 8 6
mb "Bone01"
m "Bone03"
v 5.79632 -14.922 -0.076965
vn -18.3903 0.0212279 61.3009
vt 0 1
v 5.7963 -14.9377 -0.076965
vn -18.461 -61.2796 -6.64016e-06
vt 0 1
v 5.7963 -14.9377 -0.09259
vn -18.461 -61.2796 -6.64016e-06
vt 0 1
v 5.79632 -14.922 -0.09259
vn -18.3902 0.0212278 -61.3009
vt 0 1
v 5.77287 -14.929 -0.0839963
vn -64 0.0738751 -2.29021e-05
vt 0 1
v 5.77287 -14.9306 -0.0839963
vn -64 0.0738751 -2.29021e-05
vt 0 1
v 5.77287 -14.9306 -0.0855588
vn -64 0.0738751 -2.29021e-05
vt 0 1
v 5.77287 -14.929 -0.0855588
vn -64 0.0738751 -2.29021e-05
vt 0 1
v 5.80412 -14.9299 -0.0847775
vn 45.2548 -0.0522376 45.2548
vt 0 1
v 5.77287 -14.9306 -0.0839963
vn -18.461 -61.2796 -6.64016e-06
vt 0 1
v 5.77287 -14.9306 -0.0855588
vn -18.461 -61.2796 -6.64016e-06
vt 0 1
v 5.77287 -14.929 -0.0839963
vn -18.3903 0.0212279 61.3009
vt 0 1
v 5.7963 -14.9377 -0.076965
vn -18.3903 0.0212279 61.3009
vt 0 1
v 5.77287 -14.9306 -0.0839963
vn -18.3903 0.0212279 61.3009
vt 0 1
v 5.77287 -14.929 -0.0855588
vn -18.3902 0.0212278 -61.3009
vt 0 1
v 5.77287 -14.9306 -0.0855588
vn -18.3902 0.0212278 -61.3009
vt 0 1
v 5.7963 -14.9377 -0.09259
vn -18.3902 0.0212278 -61.3009
vt 0 1
v 5.77287 -14.929 -0.0839963
vn -18.3195 61.3221 -6.52158e-06
vt 0 1
v 5.79632 -14.922 -0.076965
vn -18.3195 61.3221 -6.52158e-06
vt 0 1
v 5.77287 -14.929 -0.0855588
vn -18.3195 61.3221 -6.52158e-06
vt 0 1
v 5.79632 -14.922 -0.09259
vn -18.3195 61.3221 -6.52158e-06
vt 0 1
v 5.79632 -14.922 -0.076965
vn 45.2548 -0.0522376 45.2548
vt 0 1
v 5.7963 -14.9377 -0.076965
vn 45.2548 -0.0522376 45.2548
vt 0 1
v 5.80412 -14.9299 -0.0847775
vn 45.2026 -45.307 1.61505e-05
vt 0 1
v 5.7963 -14.9377 -0.076965
vn 45.2026 -45.307 1.61505e-05
vt 0 1
v 5.7963 -14.9377 -0.09259
vn 45.2026 -45.307 1.61505e-05
vt 0 1
v 5.80412 -14.9299 -0.0847775
vn 45.2548 -0.0522376 -45.2548
vt 0 1
v 5.7963 -14.9377 -0.09259
vn 45.2548 -0.0522376 -45.2548
vt 0 1
v 5.79632 -14.922 -0.09259
vn 45.2548 -0.0522376 -45.2548
vt 0 1
v 5.80412 -14.9299 -0.0847775
vn 45.3071 45.2025 1.6238e-05
vt 0 1
v 5.79632 -14.922 -0.09259
vn 45.3071 45.2025 1.6238e-05
vt 0 1
v 5.79632 -14.922 -0.076965
vn 45.3071 45.2025 1.6238e-05
vt 0 1
fg 1
f 30 31 32
f 27 28 29
f 24 25 26
f 9 22 23
f 21 20 19
f 18 19 20
f 17 16 4
f 15 4 16
f 14 13 12
f 1 12 13
f 11 3 10
f 2 10 3
f 7 6 8
f 5 8 6
mb "Bone03"
m "Dummy01"
v 10.826 -15.992 -0.0769634
vn 47.5705 -0.118397 42.8139
vt 0 1
v 10.826 -15.9764 -0.0769634
vn -0.11842 -47.5705 42.8139
vt 0 1
v 10.8416 -15.9764 -0.0769634
vn -0.11842 -47.5705 42.8139
vt 0 1
v 10.8416 -15.9921 -0.0769634
vn -47.5705 0.118397 42.8139
vt 0 1
v 10.833 -15.985 -0.0847758
vn -2.78471e-06 -1.42085e-08 64
vt 0 1
v 10.833 -15.9835 -0.0847758
vn -2.78471e-06 -1.42085e-08 64
vt 0 1
v 10.8346 -15.9835 -0.0847758
vn -2.78471e-06 -1.42085e-08 64
vt 0 1
v 10.8346 -15.985 -0.0847758
vn -2.78471e-06 -1.42085e-08 64
vt 0 1
v 10.8338 -15.9842 -0.0847759
vn -45.2547 0.112634 -45.2548
vt 0 1
v 10.833 -15.9835 -0.0847758
vn -0.11842 -47.5705 42.8139
vt 0 1
v 10.8346 -15.9835 -0.0847758
vn -0.11842 -47.5705 42.8139
vt 0 1
v 10.833 -15.985 -0.0847758
vn 47.5705 -0.118397 42.8139
vt 0 1
v 10.826 -15.9764 -0.0769634
vn 47.5705 -0.118397 42.8139
vt 0 1
v 10.833 -15.9835 -0.0847758
vn 47.5705 -0.118397 42.8139
vt 0 1
v 10.8346 -15.985 -0.0847758
vn -47.5705 0.118397 42.8139
vt 0 1
v 10.8346 -15.9835 -0.0847758
vn -47.5705 0.118397 42.8139
vt 0 1
v 10.8416 -15.9764 -0.0769634
vn -47.5705 0.118397 42.8139
vt 0 1
v 10.833 -15.985 -0.0847758
vn 0.118416 47.5705 42.8139
vt 0 1
v 10.826 -15.992 -0.0769634
vn 0.118416 47.5705 42.8139
vt 0 1
v 10.8346 -15.985 -0.0847758
vn 0.118416 47.5705 42.8139
vt 0 1
v 10.8416 -15.9921 -0.0769634
vn 0.118416 47.5705 42.8139
vt 0 1
v 10.826 -15.992 -0.0769634
vn -45.2547 0.112634 -45.2548
vt 0 1
v 10.826 -15.9764 -0.0769634
vn -45.2547 0.112634 -45.2548
vt 0 1
v 10.8338 -15.9842 -0.0847759
vn 0.112655 45.2547 -45.2548
vt 0 1
v 10.826 -15.9764 -0.0769634
vn 0.112655 45.2547 -45.2548
vt 0 1
v 10.8416 -15.9764 -0.0769634
vn 0.112655 45.2547 -45.2548
vt 0 1
v 10.8338 -15.9842 -0.0847759
vn 45.2547 -0.112634 -45.2548
vt 0 1
v 10.8416 -15.9764 -0.0769634
vn 45.2547 -0.112634 -45.2548
vt 0 1
v 10.8416 -15.9921 -0.0769634
vn 45.2547 -0.112634 -45.2548
vt 0 1
v 10.8338 -15.9842 -0.0847759
vn -0.112652 -45.2547 -45.2548
vt 0 1
v 10.8416 -15.9921 -0.0769634
vn -0.112652 -45.2547 -45.2548
vt 0 1
v 10.826 -15.992 -0.0769634
vn -0.112652 -45.2547 -45.2548
vt 0 1
fg 1
f 30 31 32
f 27 28 29
f 24 25 26
f 9 22 23
f 21 20 19
f 18 19 20
f 17 16 4
f 15 4 16
f 14 13 12
f 1 12 13
f 11 3 10
f 2 10 3
f 7 6 8
f 5 8 6
mb "Dummy01"
m "Bone32"
v 10.7982 -15.8534 -0.0769633
vn -5.10188 -17.6684 61.3009
vt 0 1
v 10.8132 -15.8577 -0.0769633
vn 53.7929 -34.6746 3.24031e-05
vt 0 1
v 10.8132 -15.8577 -0.0925883
vn 53.7929 -34.6746 3.24031e-05
vt 0 1
v 10.7982 -15.8534 -0.0925883
vn -5.10183 -17.6684 -61.3009
vt 0 1
v 10.7985 -15.8778 -0.0839946
vn -17.755 -61.4879 1.84538e-05
vt 0 1
v 10.8 -15.8783 -0.0839946
vn -17.755 -61.4879 1.84538e-05
vt 0 1
v 10.8 -15.8783 -0.0855571
vn -17.755 -61.4879 1.84538e-05
vt 0 1
v 10.7985 -15.8778 -0.0855571
vn -17.755 -61.4879 1.84538e-05
vt 0 1
v 10.8079 -15.848 -0.0847758
vn 12.5546 43.4785 45.2548
vt 0 1
v 10.8 -15.8783 -0.0839946
vn 53.7929 -34.6746 3.24031e-05
vt 0 1
v 10.8 -15.8783 -0.0855571
vn 53.7929 -34.6746 3.24031e-05
vt 0 1
v 10.7985 -15.8778 -0.0839946
vn -5.10188 -17.6684 61.3009
vt 0 1
v 10.8132 -15.8577 -0.0769633
vn -5.10188 -17.6684 61.3009
vt 0 1
v 10.8 -15.8783 -0.0839946
vn -5.10188 -17.6684 61.3009
vt 0 1
v 10.7985 -15.8778 -0.0855571
vn -5.10183 -17.6684 -61.3009
vt 0 1
v 10.8 -15.8783 -0.0855571
vn -5.10183 -17.6684 -61.3009
vt 0 1
v 10.8132 -15.8577 -0.0925883
vn -5.10183 -17.6684 -61.3009
vt 0 1
v 10.7985 -15.8778 -0.0839946
vn -63.9966 -0.66227 -2.17978e-05
vt 0 1
v 10.7982 -15.8534 -0.0769633
vn -63.9966 -0.66227 -2.17978e-05
vt 0 1
v 10.7985 -15.8778 -0.0855571
vn -63.9966 -0.66227 -2.17978e-05
vt 0 1
v 10.7982 -15.8534 -0.0925883
vn -63.9966 -0.66227 -2.17978e-05
vt 0 1
v 10.7982 -15.8534 -0.0769633
vn 12.5546 43.4785 45.2548
vt 0 1
v 10.8132 -15.8577 -0.0769633
vn 12.5546 43.4785 45.2548
vt 0 1
v 10.8079 -15.848 -0.0847758
vn 56.0332 30.9239 6.95786e-06
vt 0 1
v 10.8132 -15.8577 -0.0769633
vn 56.0332 30.9239 6.95786e-06
vt 0 1
v 10.8132 -15.8577 -0.0925883
vn 56.0332 30.9239 6.95786e-06
vt 0 1
v 10.8079 -15.848 -0.0847758
vn 12.5547 43.4785 -45.2548
vt 0 1
v 10.8132 -15.8577 -0.0925883
vn 12.5547 43.4785 -45.2548
vt 0 1
v 10.7982 -15.8534 -0.0925883
vn 12.5547 43.4785 -45.2548
vt 0 1
v 10.8079 -15.848 -0.0847758
vn -30.9239 56.0332 -3.30554e-05
vt 0 1
v 10.7982 -15.8534 -0.0925883
vn -30.9239 56.0332 -3.30554e-05
vt 0 1
v 10.7982 -15.8534 -0.0769633
vn -30.9239 56.0332 -3.30554e-05
vt 0 1
fg 1
f 30 31 32
f 27 28 29
f 24 25 26
f 9 22 23
f 21 20 19
f 18 19 20
f 17 16 4
f 15 4 16
f 14 13 12
f 1 12 13
f 11 3 10
f 2 10 3
f 7 6 8
f 5 8 6
mb "Bone32"
m "Bone09"
v 19.2334 -14.8878 -0.0613357
vn -2.28753e-05 3.57939e-08 64
vt 1 0
v 19.2559 -14.9289 -0.0613357
vn 30.6651 -56.1752 1.09423e-05
vt 1 0
v 19.2559 -14.9289 -0.108211
vn 30.6651 -56.1752 1.09423e-05
vt 0 0
v 19.2334 -14.8878 -0.108211
vn 2.28753e-05 -3.57939e-08 -64
vt 0 0
v 18.5107 -15.2823 -0.061336
vn -56.1752 -30.6651 -2.01191e-05
vt 1 0
v 18.5332 -15.3234 -0.061336
vn -56.1752 -30.6651 -2.01191e-05
vt 0 0
v 18.5332 -15.3234 -0.108211
vn -56.1752 -30.6651 -2.01191e-05
vt 0 1
v 18.5107 -15.2823 -0.108211
vn -56.1752 -30.6651 -2.01191e-05
vt 1 1
v 19.2652 -14.8971 -0.0847732
vn 39.7219 21.6835 45.2548
vt 0 0
v 18.5332 -15.3234 -0.061336
vn 30.6651 -56.1752 1.09423e-05
vt 1 1
v 18.5332 -15.3234 -0.108211
vn 30.6651 -56.1752 1.09423e-05
vt 0 1
v 18.5107 -15.2823 -0.061336
vn -2.28753e-05 3.57939e-08 64
vt 1 1
v 19.2559 -14.9289 -0.0613357
vn -2.28753e-05 3.57939e-08 64
vt 0 0
v 18.5332 -15.3234 -0.061336
vn -2.28753e-05 3.57939e-08 64
vt 0 1
v 18.5107 -15.2823 -0.108211
vn 2.28753e-05 -3.57939e-08 -64
vt 0 1
v 18.5332 -15.3234 -0.108211
vn 2.28753e-05 -3.57939e-08 -64
vt 1 1
v 19.2559 -14.9289 -0.108211
vn 2.28753e-05 -3.57939e-08 -64
vt 1 0
v 18.5107 -15.2823 -0.061336
vn -30.6651 56.1752 -1.09423e-05
vt 0 1
v 19.2334 -14.8878 -0.0613357
vn -30.6651 56.1752 -1.09423e-05
vt 0 0
v 18.5107 -15.2823 -0.108211
vn -30.6651 56.1752 -1.09423e-05
vt 1 1
v 19.2334 -14.8878 -0.108211
vn -30.6651 56.1752 -1.09423e-05
vt 1 0
v 19.2334 -14.8878 -0.0613357
vn 39.7219 21.6835 45.2548
vt 1 0
v 19.2559 -14.9289 -0.0613357
vn 39.7219 21.6835 45.2548
vt 1 1
v 19.2652 -14.8971 -0.0847732
vn 61.4053 -18.0384 2.19637e-05
vt 0 0
v 19.2559 -14.9289 -0.0613357
vn 61.4053 -18.0384 2.19637e-05
vt 1 0
v 19.2559 -14.9289 -0.108211
vn 61.4053 -18.0384 2.19637e-05
vt 1 1
v 19.2652 -14.8971 -0.0847732
vn 39.7219 21.6835 -45.2548
vt 0 0
v 19.2559 -14.9289 -0.108211
vn 39.7219 21.6835 -45.2548
vt 1 0
v 19.2334 -14.8878 -0.108211
vn 39.7219 21.6835 -45.2548
vt 1 1
v 19.2652 -14.8971 -0.0847732
vn 18.0384 61.4053 6.489e-06
vt 1 1
v 19.2334 -14.8878 -0.108211
vn 18.0384 61.4053 6.489e-06
vt 0 1
v 19.2334 -14.8878 -0.0613357
vn 18.0384 61.4053 6.489e-06
vt 0 0
fg 1
f 30 31 32
f 27 28 29
f 24 25 26
f 9 22 23
f 21 20 19
f 18 19 20
f 17 16 4
f 15 4 16
f 14 13 12
f 1 12 13
f 11 3 10
f 2 10 3
f 7 6 8
f 5 8 6
mm 1
mb "Bone09"
m "Bone14"
v 18.4989 -15.279 -0.061336
vn -2.28753e-05 3.57939e-08 64
vt 1 0
v 18.4981 -15.3259 -0.061336
vn -1.09521 -63.9906 -4.2737e-07
vt 1 0
v 18.4981 -15.3259 -0.108211
vn -1.09521 -63.9906 -4.2737e-07
vt 0 0
v 18.4989 -15.279 -0.108211
vn 2.28753e-05 -3.57939e-08 -64
vt 0 0
v 17.8247 -15.2675 -0.0613362
vn -63.9906 1.09518 -2.28982e-05
vt 1 0
v 17.8239 -15.3144 -0.0613362
vn -63.9906 1.09518 -2.28982e-05
vt 0 0
v 17.8239 -15.3144 -0.108211
vn -63.9906 1.09518 -2.28982e-05
vt 0 1
v 17.8247 -15.2675 -0.108211
vn -63.9906 1.09518 -2.28982e-05
vt 1 1
v 18.5219 -15.3029 -0.0847735
vn 45.2482 -0.774411 45.2548
vt 0 0
v 17.8239 -15.3144 -0.0613362
vn -1.09521 -63.9906 -4.2737e-07
vt 1 1
v 17.8239 -15.3144 -0.108211
vn -1.09521 -63.9906 -4.2737e-07
vt 0 1
v 17.8247 -15.2675 -0.0613362
vn -2.28753e-05 3.57939e-08 64
vt 1 1
v 18.4981 -15.3259 -0.061336
vn -2.28753e-05 3.57939e-08 64
vt 0 0
v 17.8239 -15.3144 -0.0613362
vn -2.28753e-05 3.57939e-08 64
vt 0 1
v 17.8247 -15.2675 -0.108211
vn 2.28753e-05 -3.57939e-08 -64
vt 0 1
v 17.8239 -15.3144 -0.108211
vn 2.28753e-05 -3.57939e-08 -64
vt 1 1
v 18.4981 -15.3259 -0.108211
vn 2.28753e-05 -3.57939e-08 -64
vt 1 0
v 17.8247 -15.2675 -0.0613362
vn 1.09521 63.9906 4.2737e-07
vt 0 1
v 18.4989 -15.279 -0.061336
vn 1.09521 63.9906 4.2737e-07
vt 0 0
v 17.8247 -15.2675 -0.108211
vn 1.09521 63.9906 4.2737e-07
vt 1 1
v 18.4989 -15.279 -0.108211
vn 1.09521 63.9906 4.2737e-07
vt 1 0
v 18.4989 -15.279 -0.061336
vn 45.2482 -0.774411 45.2548
vt 1 0
v 18.4981 -15.3259 -0.061336
vn 45.2482 -0.774411 45.2548
vt 1 1
v 18.5219 -15.3029 -0.0847735
vn 44.4738 -46.0226 1.58893e-05
vt 0 0
v 18.4981 -15.3259 -0.061336
vn 44.4738 -46.0226 1.58893e-05
vt 1 0
v 18.4981 -15.3259 -0.108211
vn 44.4738 -46.0226 1.58893e-05
vt 1 1
v 18.5219 -15.3029 -0.0847735
vn 45.2482 -0.774411 -45.2548
vt 0 0
v 18.4981 -15.3259 -0.108211
vn 45.2482 -0.774411 -45.2548
vt 1 0
v 18.4989 -15.279 -0.108211
vn 45.2482 -0.774411 -45.2548
vt 1 1
v 18.5219 -15.3029 -0.0847735
vn 46.0226 44.4738 1.64937e-05
vt 1 1
v 18.4989 -15.279 -0.108211
vn 46.0226 44.4738 1.64937e-05
vt 0 1
v 18.4989 -15.279 -0.061336
vn 46.0226 44.4738 1.64937e-05
vt 0 0
fg 1
f 30 31 32
f 27 28 29
f 24 25 26
f 9 22 23
f 21 20 19
f 18 19 20
f 17 16 4
f 15 4 16
f 14 13 12
f 1 12 13
f 11 3 10
f 2 10 3
f 7 6 8
f 5 8 6
mm 1
mb "Bone14"
m "Bone15"
v 17.8009 -15.2675 -0.0613362
vn -2.28753e-05 3.57939e-08 64
vt 1 0
v 17.8009 -15.3144 -0.0613362
vn -0.013344 -64 -4.02334e-08
vt 1 0
v 17.8009 -15.3144 -0.108211
vn -0.013344 -64 -4.02334e-08
vt 0 0
v 17.8009 -15.2675 -0.108211
vn 2.28753e-05 -3.57939e-08 -64
vt 0 0
v 16.706 -15.2673 -0.0613366
vn -64 0.0133158 -2.29021e-05
vt 1 0
v 16.706 -15.3141 -0.0613366
vn -64 0.0133158 -2.29021e-05
vt 0 0
v 16.706 -15.3141 -0.108212
vn -64 0.0133158 -2.29021e-05
vt 0 1
v 16.706 -15.2673 -0.108212
vn -64 0.0133158 -2.29021e-05
vt 1 1
v 17.8243 -15.2909 -0.0847737
vn 45.2548 -0.00941568 45.2548
vt 0 0
v 16.706 -15.3141 -0.0613366
vn -0.013344 -64 -4.02334e-08
vt 1 1
v 16.706 -15.3141 -0.108212
vn -0.013344 -64 -4.02334e-08
vt 0 1
v 16.706 -15.2673 -0.0613366
vn -2.28753e-05 3.57939e-08 64
vt 1 1
v 17.8009 -15.3144 -0.0613362
vn -2.28753e-05 3.57939e-08 64
vt 0 0
v 16.706 -15.3141 -0.0613366
vn -2.28753e-05 3.57939e-08 64
vt 0 1
v 16.706 -15.2673 -0.108212
vn 2.28753e-05 -3.57939e-08 -64
vt 0 1
v 16.706 -15.3141 -0.108212
vn 2.28753e-05 -3.57939e-08 -64
vt 1 1
v 17.8009 -15.3144 -0.108211
vn 2.28753e-05 -3.57939e-08 -64
vt 1 0
v 16.706 -15.2673 -0.0613366
vn 0.013344 64 4.02334e-08
vt 0 1
v 17.8009 -15.2675 -0.0613362
vn 0.013344 64 4.02334e-08
vt 0 0
v 16.706 -15.2673 -0.108212
vn 0.013344 64 4.02334e-08
vt 1 1
v 17.8009 -15.2675 -0.108211
vn 0.013344 64 4.02334e-08
vt 1 0
v 17.8009 -15.2675 -0.0613362
vn 45.2548 -0.00941568 45.2548
vt 1 0
v 17.8009 -15.3144 -0.0613362
vn 45.2548 -0.00941568 45.2548
vt 1 1
v 17.8243 -15.2909 -0.0847737
vn 45.2454 -45.2642 1.61658e-05
vt 0 0
v 17.8009 -15.3144 -0.0613362
vn 45.2454 -45.2642 1.61658e-05
vt 1 0
v 17.8009 -15.3144 -0.108211
vn 45.2454 -45.2642 1.61658e-05
vt 1 1
v 17.8243 -15.2909 -0.0847737
vn 45.2549 -0.00941574 -45.2548
vt 0 0
v 17.8009 -15.3144 -0.108211
vn 45.2549 -0.00941574 -45.2548
vt 1 0
v 17.8009 -15.2675 -0.108211
vn 45.2549 -0.00941574 -45.2548
vt 1 1
v 17.8243 -15.2909 -0.0847737
vn 45.2643 45.2454 1.62227e-05
vt 1 1
v 17.8009 -15.2675 -0.108211
vn 45.2643 45.2454 1.62227e-05
vt 0 1
v 17.8009 -15.2675 -0.0613362
vn 45.2643 45.2454 1.62227e-05
vt 0 0
fg 1
f 30 31 32
f 27 28 29
f 24 25 26
f 9 22 23
f 21 20 19
f 18 19 20
f 17 16 4
f 15 4 16
f 14 13 12
f 1 12 13
f 11 3 10
f 2 10 3
f 7 6 8
f 5 8 6
mm 1
mb "Bone15"
m "Bone16"
v 16.6808 -15.2692 -0.0613366
vn -2.28753e-05 3.57938e-08 64
vt 1 0
v 16.6845 -15.3159 -0.0613366
vn 5.10864 -63.7958 1.79276e-06
vt 1 0
v 16.6845 -15.3159 -0.108212
vn 5.10864 -63.7958 1.79276e-06
vt 0 0
v 16.6808 -15.2692 -0.108212
vn 2.28753e-05 -3.57938e-08 -64
vt 0 0
v 15.6213 -15.354 -0.061337
vn -63.7958 -5.10866 -2.28319e-05
vt 1 0
v 15.6251 -15.4008 -0.061337
vn -63.7958 -5.10866 -2.28319e-05
vt 0 0
v 15.6251 -15.4008 -0.108212
vn -63.7958 -5.10866 -2.28319e-05
vt 0 1
v 15.6213 -15.354 -0.108212
vn -63.7958 -5.10866 -2.28319e-05
vt 1 1
v 16.706 -15.2907 -0.0847742
vn 45.1104 3.61237 45.2548
vt 0 0
v 15.6251 -15.4008 -0.061337
vn 5.10864 -63.7958 1.79276e-06
vt 1 1
v 15.6251 -15.4008 -0.108212
vn 5.10864 -63.7958 1.79276e-06
vt 0 1
v 15.6213 -15.354 -0.061337
vn -2.28753e-05 3.57938e-08 64
vt 1 1
v 16.6845 -15.3159 -0.0613366
vn -2.28753e-05 3.57938e-08 64
vt 0 0
v 15.6251 -15.4008 -0.061337
vn -2.28753e-05 3.57938e-08 64
vt 0 1
v 15.6213 -15.354 -0.108212
vn 2.28753e-05 -3.57938e-08 -64
vt 0 1
v 15.6251 -15.4008 -0.108212
vn 2.28753e-05 -3.57938e-08 -64
vt 1 1
v 16.6845 -15.3159 -0.108212
vn 2.28753e-05 -3.57938e-08 -64
vt 1 0
v 15.6213 -15.354 -0.061337
vn -5.10864 63.7958 -1.79276e-06
vt 0 1
v 16.6808 -15.2692 -0.0613366
vn -5.10864 63.7958 -1.79276e-06
vt 0 0
v 15.6213 -15.354 -0.108212
vn -5.10864 63.7958 -1.79276e-06
vt 1 1
v 16.6808 -15.2692 -0.108212
vn -5.10864 63.7958 -1.79276e-06
vt 1 0
v 16.6808 -15.2692 -0.0613366
vn 45.1104 3.61237 45.2548
vt 1 0
v 16.6845 -15.3159 -0.0613366
vn 45.1104 3.61237 45.2548
vt 1 1
v 16.706 -15.2907 -0.0847742
vn 48.7228 -41.4981 1.74123e-05
vt 0 0
v 16.6845 -15.3159 -0.0613366
vn 48.7228 -41.4981 1.74123e-05
vt 1 0
v 16.6845 -15.3159 -0.108212
vn 48.7228 -41.4981 1.74123e-05
vt 1 1
v 16.706 -15.2907 -0.0847742
vn 45.1105 3.61237 -45.2548
vt 0 0
v 16.6845 -15.3159 -0.108212
vn 45.1105 3.61237 -45.2548
vt 1 0
v 16.6808 -15.2692 -0.108212
vn 45.1105 3.61237 -45.2548
vt 1 1
v 16.706 -15.2907 -0.0847742
vn 41.4981 48.7228 1.48769e-05
vt 1 1
v 16.6808 -15.2692 -0.108212
vn 41.4981 48.7228 1.48769e-05
vt 0 1
v 16.6808 -15.2692 -0.0613366
vn 41.4981 48.7228 1.48769e-05
vt 0 0
fg 1
f 30 31 32
f 27 28 29
f 24 25 26
f 9 22 23
f 21 20 19
f 18 19 20
f 17 16 4
f 15 4 16
f 14 13 12
f 1 12 13
f 11 3 10
f 2 10 3
f 7 6 8
f 5 8 6
mm 1
mb "Bone16"
m "Bone17"
v 15.5971 -15.357 -0.061337
vn -2.28753e-05 3.57938e-08 64
vt 1 0
v 15.6027 -15.4035 -0.061337
vn 7.712 -63.5337 2.72451e-06
vt 1 0
v 15.6027 -15.4035 -0.108212
vn 7.712 -63.5337 2.72451e-06
vt 0 0
v 15.5971 -15.357 -0.108212
vn 2.28753e-05 -3.57938e-08 -64
vt 0 0
v 14.4789 -15.4927 -0.0613374
vn -63.5336 -7.71202 -2.27395e-05
vt 1 0
v 14.4845 -15.5392 -0.0613374
vn -63.5336 -7.71202 -2.27395e-05
vt 0 0
v 14.4845 -15.5392 -0.108212
vn -63.5336 -7.71202 -2.27395e-05
vt 0 1
v 14.4789 -15.4927 -0.108212
vn -63.5336 -7.71202 -2.27395e-05
vt 1 1
v 15.6232 -15.3774 -0.0847745
vn 44.9251 5.45322 45.2548
vt 0 0
v 14.4845 -15.5392 -0.0613374
vn 7.712 -63.5337 2.72451e-06
vt 1 1
v 14.4845 -15.5392 -0.108212
vn 7.712 -63.5337 2.72451e-06
vt 0 1
v 14.4789 -15.4927 -0.0613374
vn -2.28753e-05 3.57938e-08 64
vt 1 1
v 15.6027 -15.4035 -0.061337
vn -2.28753e-05 3.57938e-08 64
vt 0 0
v 14.4845 -15.5392 -0.0613374
vn -2.28753e-05 3.57938e-08 64
vt 0 1
v 14.4789 -15.4927 -0.108212
vn 2.28753e-05 -3.57938e-08 -64
vt 0 1
v 14.4845 -15.5392 -0.108212
vn 2.28753e-05 -3.57938e-08 -64
vt 1 1
v 15.6027 -15.4035 -0.108212
vn 2.28753e-05 -3.57938e-08 -64
vt 1 0
v 14.4789 -15.4927 -0.0613374
vn -7.712 63.5337 -2.72451e-06
vt 0 1
v 15.5971 -15.357 -0.061337
vn -7.712 63.5337 -2.72451e-06
vt 0 0
v 14.4789 -15.4927 -0.108212
vn -7.712 63.5337 -2.72451e-06
vt 1 1
v 15.5971 -15.357 -0.108212
vn -7.712 63.5337 -2.72451e-06
vt 1 0
v 15.5971 -15.357 -0.061337
vn 44.9251 5.45322 45.2548
vt 1 0
v 15.6027 -15.4035 -0.061337
vn 44.9251 5.45322 45.2548
vt 1 1
v 15.6232 -15.3774 -0.0847745
vn 50.3783 -39.4718 1.80058e-05
vt 0 0
v 15.6027 -15.4035 -0.061337
vn 50.3783 -39.4718 1.80058e-05
vt 1 0
v 15.6027 -15.4035 -0.108212
vn 50.3783 -39.4718 1.80058e-05
vt 1 1
v 15.6232 -15.3774 -0.0847745
vn 44.9251 5.45323 -45.2548
vt 0 0
v 15.6027 -15.4035 -0.108212
vn 44.9251 5.45323 -45.2548
vt 1 0
v 15.5971 -15.357 -0.108212
vn 44.9251 5.45323 -45.2548
vt 1 1
v 15.6232 -15.3774 -0.0847745
vn 39.4719 50.3783 1.41528e-05
vt 1 1
v 15.5971 -15.357 -0.108212
vn 39.4719 50.3783 1.41528e-05
vt 0 1
v 15.5971 -15.357 -0.061337
vn 39.4719 50.3783 1.41528e-05
vt 0 0
fg 1
f 30 31 32
f 27 28 29
f 24 25 26
f 9 22 23
f 21 20 19
f 18 19 20
f 17 16 4
f 15 4 16
f 14 13 12
f 1 12 13
f 11 3 10
f 2 10 3
f 7 6 8
f 5 8 6
mm 1
mb "Bone17"
m "Bone18"
v 14.4558 -15.4953 -0.0613375
vn -2.28753e-05 3.57937e-08 64
vt 1 0
v 14.4611 -15.5419 -0.0613375
vn 7.22785 -63.5906 2.55123e-06
vt 1 0
v 14.4611 -15.5419 -0.108212
vn 7.22785 -63.5906 2.55123e-06
vt 0 0
v 14.4558 -15.4953 -0.108212
vn 2.28753e-05 -3.57937e-08 -64
vt 0 0
v 13.3227 -15.6241 -0.0613379
vn -63.5905 -7.22787 -2.27596e-05
vt 1 0
v 13.328 -15.6707 -0.0613379
vn -63.5905 -7.22787 -2.27596e-05
vt 0 0
v 13.328 -15.6707 -0.108213
vn -63.5905 -7.22787 -2.27596e-05
vt 0 1
v 13.3227 -15.6241 -0.108213
vn -63.5905 -7.22787 -2.27596e-05
vt 1 1
v 14.4817 -15.516 -0.084775
vn 44.9653 5.11088 45.2548
vt 0 0
v 13.328 -15.6707 -0.0613379
vn 7.22785 -63.5906 2.55123e-06
vt 1 1
v 13.328 -15.6707 -0.108213
vn 7.22785 -63.5906 2.55123e-06
vt 0 1
v 13.3227 -15.6241 -0.0613379
vn -2.28753e-05 3.57937e-08 64
vt 1 1
v 14.4611 -15.5419 -0.0613375
vn -2.28753e-05 3.57937e-08 64
vt 0 0
v 13.328 -15.6707 -0.0613379
vn -2.28753e-05 3.57937e-08 64
vt 0 1
v 13.3227 -15.6241 -0.108213
vn 2.28753e-05 -3.57937e-08 -64
vt 0 1
v 13.328 -15.6707 -0.108213
vn 2.28753e-05 -3.57937e-08 -64
vt 1 1
v 14.4611 -15.5419 -0.108212
vn 2.28753e-05 -3.57937e-08 -64
vt 1 0
v 13.3227 -15.6241 -0.0613379
vn -7.22785 63.5906 -2.55123e-06
vt 0 1
v 14.4558 -15.4953 -0.0613375
vn -7.22785 63.5906 -2.55123e-06
vt 0 0
v 13.3227 -15.6241 -0.108213
vn -7.22785 63.5906 -2.55123e-06
vt 1 1
v 14.4558 -15.4953 -0.108212
vn -7.22785 63.5906 -2.55123e-06
vt 1 0
v 14.4558 -15.4953 -0.0613375
vn 44.9653 5.11088 45.2548
vt 1 0
v 14.4611 -15.5419 -0.0613375
vn 44.9653 5.11088 45.2548
vt 1 1
v 14.4817 -15.516 -0.084775
vn 50.0762 -39.8544 1.78975e-05
vt 0 0
v 14.4611 -15.5419 -0.0613375
vn 50.0762 -39.8544 1.78975e-05
vt 1 0
v 14.4611 -15.5419 -0.108212
vn 50.0762 -39.8544 1.78975e-05
vt 1 1
v 14.4817 -15.516 -0.084775
vn 44.9653 5.11088 -45.2548
vt 0 0
v 14.4611 -15.5419 -0.108212
vn 44.9653 5.11088 -45.2548
vt 1 0
v 14.4558 -15.4953 -0.108212
vn 44.9653 5.11088 -45.2548
vt 1 1
v 14.4817 -15.516 -0.084775
vn 39.8545 50.0762 1.42895e-05
vt 1 1
v 14.4558 -15.4953 -0.108212
vn 39.8545 50.0762 1.42895e-05
vt 0 1
v 14.4558 -15.4953 -0.0613375
vn 39.8545 50.0762 1.42895e-05
vt 0 0
fg 1
f 30 31 32
f 27 28 29
f 24 25 26
f 9 22 23
f 21 20 19
f 18 19 20
f 17 16 4
f 15 4 16
f 14 13 12
f 1 12 13
f 11 3 10
f 2 10 3
f 7 6 8
f 5 8 6
mm 1
mb "Bone18"
m "Bone19"
v 13.2996 -15.6265 -0.0613379
vn -2.28753e-05 3.57939e-08 64
vt 1 0
v 13.3044 -15.6731 -0.0613379
vn 6.56683 -63.6622 2.31465e-06
vt 1 0
v 13.3044 -15.6731 -0.108213
vn 6.56683 -63.6622 2.31465e-06
vt 0 0
v 13.2996 -15.6265 -0.108213
vn 2.28753e-05 -3.57939e-08 -64
vt 0 0
v 12.1584 -15.7442 -0.0613383
vn -63.6622 -6.56686 -2.27849e-05
vt 1 0
v 12.1632 -15.7908 -0.0613383
vn -63.6622 -6.56686 -2.27849e-05
vt 0 0
v 12.1632 -15.7908 -0.108213
vn -63.6622 -6.56686 -2.27849e-05
vt 0 1
v 12.1584 -15.7442 -0.108213
vn -63.6622 -6.56686 -2.27849e-05
vt 1 1
v 13.3253 -15.6474 -0.0847754
vn 45.016 4.64347 45.2548
vt 0 0
v 12.1632 -15.7908 -0.0613383
vn 6.56683 -63.6622 2.31465e-06
vt 1 1
v 12.1632 -15.7908 -0.108213
vn 6.56683 -63.6622 2.31465e-06
vt 0 1
v 12.1584 -15.7442 -0.0613383
vn -2.28753e-05 3.57939e-08 64
vt 1 1
v 13.3044 -15.6731 -0.0613379
vn -2.28753e-05 3.57939e-08 64
vt 0 0
v 12.1632 -15.7908 -0.0613383
vn -2.28753e-05 3.57939e-08 64
vt 0 1
v 12.1584 -15.7442 -0.108213
vn 2.28753e-05 -3.57939e-08 -64
vt 0 1
v 12.1632 -15.7908 -0.108213
vn 2.28753e-05 -3.57939e-08 -64
vt 1 1
v 13.3044 -15.6731 -0.108213
vn 2.28753e-05 -3.57939e-08 -64
vt 1 0
v 12.1584 -15.7442 -0.0613383
vn -6.56683 63.6622 -2.31465e-06
vt 0 1
v 13.2996 -15.6265 -0.0613379
vn -6.56683 63.6622 -2.31465e-06
vt 0 0
v 12.1584 -15.7442 -0.108213
vn -6.56683 63.6622 -2.31465e-06
vt 1 1
v 13.2996 -15.6265 -0.108213
vn -6.56683 63.6622 -2.31465e-06
vt 1 0
v 13.2996 -15.6265 -0.0613379
vn 45.016 4.64347 45.2548
vt 1 0
v 13.3044 -15.6731 -0.0613379
vn 45.016 4.64347 45.2548
vt 1 1
v 13.3253 -15.6474 -0.0847754
vn 49.6595 -40.3725 1.77481e-05
vt 0 0
v 13.3044 -15.6731 -0.0613379
vn 49.6595 -40.3725 1.77481e-05
vt 1 0
v 13.3044 -15.6731 -0.108213
vn 49.6595 -40.3725 1.77481e-05
vt 1 1
v 13.3253 -15.6474 -0.0847754
vn 45.016 4.64347 -45.2548
vt 0 0
v 13.3044 -15.6731 -0.108213
vn 45.016 4.64347 -45.2548
vt 1 0
v 13.2996 -15.6265 -0.108213
vn 45.016 4.64347 -45.2548
vt 1 1
v 13.3253 -15.6474 -0.0847754
vn 40.3725 49.6594 1.44747e-05
vt 1 1
v 13.2996 -15.6265 -0.108213
vn 40.3725 49.6594 1.44747e-05
vt 0 1
v 13.2996 -15.6265 -0.0613379
vn 40.3725 49.6594 1.44747e-05
vt 0 0
fg 1
f 30 31 32
f 27 28 29
f 24 25 26
f 9 22 23
f 21 20 19
f 18 19 20
f 17 16 4
f 15 4 16
f 14 13 12
f 1 12 13
f 11 3 10
f 2 10 3
f 7 6 8
f 5 8 6
mm 1
mb "Bone19"
m "Bone20"
v 12.1335 -15.7486 -0.0613383
vn -2.28753e-05 3.57936e-08 64
vt 1 0
v 12.1419 -15.7948 -0.0613383
vn 11.4501 -62.9674 4.06248e-06
vt 1 0
v 12.1419 -15.7948 -0.108213
vn 11.4501 -62.9674 4.06248e-06
vt 0 0
v 12.1335 -15.7486 -0.108213
vn 2.28753e-05 -3.57936e-08 -64
vt 0 0
v 11.0456 -15.9465 -0.0613387
vn -62.9674 -11.4501 -2.2539e-05
vt 1 0
v 11.054 -15.9926 -0.0613387
vn -62.9674 -11.4501 -2.2539e-05
vt 0 0
v 11.054 -15.9926 -0.108214
vn -62.9674 -11.4501 -2.2539e-05
vt 0 1
v 11.0456 -15.9465 -0.108214
vn -62.9674 -11.4501 -2.2539e-05
vt 1 1
v 12.1608 -15.7675 -0.0847758
vn 44.5247 8.09644 45.2548
vt 0 0
v 11.054 -15.9926 -0.0613387
vn 11.4501 -62.9674 4.06248e-06
vt 1 1
v 11.054 -15.9926 -0.108214
vn 11.4501 -62.9674 4.06248e-06
vt 0 1
v 11.0456 -15.9465 -0.0613387
vn -2.28753e-05 3.57936e-08 64
vt 1 1
v 12.1419 -15.7948 -0.0613383
vn -2.28753e-05 3.57936e-08 64
vt 0 0
v 11.054 -15.9926 -0.0613387
vn -2.28753e-05 3.57936e-08 64
vt 0 1
v 11.0456 -15.9465 -0.108214
vn 2.28753e-05 -3.57936e-08 -64
vt 0 1
v 11.054 -15.9926 -0.108214
vn 2.28753e-05 -3.57936e-08 -64
vt 1 1
v 12.1419 -15.7948 -0.108213
vn 2.28753e-05 -3.57936e-08 -64
vt 1 0
v 11.0456 -15.9465 -0.0613387
vn -11.4501 62.9674 -4.06248e-06
vt 0 1
v 12.1335 -15.7486 -0.0613383
vn -11.4501 62.9674 -4.06248e-06
vt 0 0
v 11.0456 -15.9465 -0.108214
vn -11.4501 62.9674 -4.06248e-06
vt 1 1
v 12.1335 -15.7486 -0.108213
vn -11.4501 62.9674 -4.06248e-06
vt 1 0
v 12.1335 -15.7486 -0.0613383
vn 44.5247 8.09644 45.2548
vt 1 0
v 12.1419 -15.7948 -0.0613383
vn 44.5247 8.09644 45.2548
vt 1 1
v 12.1608 -15.7675 -0.0847758
vn 52.6211 -36.4282 1.88101e-05
vt 0 0
v 12.1419 -15.7948 -0.0613383
vn 52.6211 -36.4282 1.88101e-05
vt 1 0
v 12.1419 -15.7948 -0.108213
vn 52.6211 -36.4282 1.88101e-05
vt 1 1
v 12.1608 -15.7675 -0.0847758
vn 44.5247 8.09644 -45.2548
vt 0 0
v 12.1419 -15.7948 -0.108213
vn 44.5247 8.09644 -45.2548
vt 1 0
v 12.1335 -15.7486 -0.108213
vn 44.5247 8.09644 -45.2548
vt 1 1
v 12.1608 -15.7675 -0.0847758
vn 36.4283 52.6211 1.30649e-05
vt 1 1
v 12.1335 -15.7486 -0.108213
vn 36.4283 52.6211 1.30649e-05
vt 0 1
v 12.1335 -15.7486 -0.0613383
vn 36.4283 52.6211 1.30649e-05
vt 0 0
fg 1
f 30 31 32
f 27 28 29
f 24 25 26
f 9 22 23
f 21 20 19
f 18 19 20
f 17 16 4
f 15 4 16
f 14 13 12
f 1 12 13
f 11 3 10
f 2 10 3
f 7 6 8
f 5 8 6
mm 1
mb "Bone20"
m "Bone21"
v 11.0219 -15.9517 -0.0613387
vn -2.28753e-05 3.57936e-08 64
vt 1 0
v 11.032 -15.9975 -0.0613387
vn 13.8795 -62.4769 4.9321e-06
vt 1 0
v 11.032 -15.9975 -0.108214
vn 13.8795 -62.4769 4.9321e-06
vt 0 0
v 11.0219 -15.9517 -0.108214
vn 2.28753e-05 -3.57936e-08 -64
vt 0 0
v 9.97614 -16.184 -0.061339
vn -62.4769 -13.8795 -2.23648e-05
vt 1 0
v 9.9863 -16.2298 -0.061339
vn -62.4769 -13.8795 -2.23648e-05
vt 0 0
v 9.9863 -16.2298 -0.108214
vn -62.4769 -13.8795 -2.23648e-05
vt 0 1
v 9.97614 -16.184 -0.108214
vn -62.4769 -13.8795 -2.23648e-05
vt 1 1
v 11.0498 -15.9695 -0.0847762
vn 44.1778 9.81429 45.2548
vt 0 0
v 9.9863 -16.2298 -0.061339
vn 13.8795 -62.4769 4.9321e-06
vt 1 1
v 9.9863 -16.2298 -0.108214
vn 13.8795 -62.4769 4.9321e-06
vt 0 1
v 9.97614 -16.184 -0.061339
vn -2.28753e-05 3.57936e-08 64
vt 1 1
v 11.032 -15.9975 -0.0613387
vn -2.28753e-05 3.57936e-08 64
vt 0 0
v 9.9863 -16.2298 -0.061339
vn -2.28753e-05 3.57936e-08 64
vt 0 1
v 9.97614 -16.184 -0.108214
vn 2.28753e-05 -3.57936e-08 -64
vt 0 1
v 9.9863 -16.2298 -0.108214
vn 2.28753e-05 -3.57936e-08 -64
vt 1 1
v 11.032 -15.9975 -0.108214
vn 2.28753e-05 -3.57936e-08 -64
vt 1 0
v 9.97614 -16.184 -0.061339
vn -13.8795 62.4769 -4.9321e-06
vt 0 1
v 11.0219 -15.9517 -0.0613387
vn -13.8795 62.4769 -4.9321e-06
vt 0 0
v 9.97614 -16.184 -0.108214
vn -13.8795 62.4769 -4.9321e-06
vt 1 1
v 11.0219 -15.9517 -0.108214
vn -13.8795 62.4769 -4.9321e-06
vt 1 0
v 11.0219 -15.9517 -0.0613387
vn 44.1778 9.81429 45.2548
vt 1 0
v 11.032 -15.9975 -0.0613387
vn 44.1778 9.81429 45.2548
vt 1 1
v 11.0498 -15.9695 -0.0847762
vn 53.9921 -34.3635 1.93018e-05
vt 0 0
v 11.032 -15.9975 -0.0613387
vn 53.9921 -34.3635 1.93018e-05
vt 1 0
v 11.032 -15.9975 -0.108214
vn 53.9921 -34.3635 1.93018e-05
vt 1 1
v 11.0498 -15.9695 -0.0847762
vn 44.1779 9.81429 -45.2548
vt 0 0
v 11.032 -15.9975 -0.108214
vn 44.1779 9.81429 -45.2548
vt 1 0
v 11.0219 -15.9517 -0.108214
vn 44.1779 9.81429 -45.2548
vt 1 1
v 11.0498 -15.9695 -0.0847762
vn 34.3636 53.9921 1.23268e-05
vt 1 1
v 11.0219 -15.9517 -0.108214
vn 34.3636 53.9921 1.23268e-05
vt 0 1
v 11.0219 -15.9517 -0.0613387
vn 34.3636 53.9921 1.23268e-05
vt 0 0
fg 1
f 30 31 32
f 27 28 29
f 24 25 26
f 9 22 23
f 21 20 19
f 18 19 20
f 17 16 4
f 15 4 16
f 14 13 12
f 1 12 13
f 11 3 10
f 2 10 3
f 7 6 8
f 5 8 6
mm 1
mb "Bone21"
m "Bone22"
v 9.98122 -16.2069 -0.0847766
vn 64 0 0
vt 0 1
v 9.98122 -16.2069 -0.0847766
vn 64 0 0
vt 0 1
v 9.98122 -16.2069 -0.0847766
vn 64 0 0
vt 0 1
v 9.98122 -16.2069 -0.0847766
vn 64 0 0
vt 0 1
v 9.952 -16.218 -0.0847766
vn 64 0 0
vt 0 1
v 9.952 -16.218 -0.0847766
vn 64 0 0
vt 0 1
v 9.952 -16.218 -0.0847766
vn 64 0 0
vt 0 1
v 9.952 -16.218 -0.0847766
vn 64 0 0
vt 0 1
v 9.98122 -16.2069 -0.0847766
vn 64 0 0
vt 0 1
fg 1
f 9 4 1
f 9 3 4
f 9 2 3
f 9 1 2
f 4 8 1
f 5 1 8
f 3 7 4
f 8 4 7
f 6 2 5
f 1 5 2
f 7 3 6
f 2 6 3
f 7 6 8
f 5 8 6
mb "Bone22"
m "Bone06"
v 1.59363 -18.3751 -0.0769666
vn 18.3902 1.14778e-07 61.3009
vt 0 1
v 1.59363 -18.3595 -0.0769666
vn 18.3903 61.3009 3.71213e-06
vt 0 1
v 1.59363 -18.3595 -0.0925916
vn 18.3903 61.3009 3.71213e-06
vt 0 1
v 1.59363 -18.3751 -0.0925916
vn 18.3903 4.39417e-06 -61.3009
vt 0 1
v 1.61706 -18.3681 -0.0839978
vn 64 7.8458e-06 1.93573e-05
vt 0 1
v 1.61706 -18.3665 -0.0839978
vn 64 7.8458e-06 1.93573e-05
vt 0 1
v 1.61706 -18.3665 -0.0855603
vn 64 7.8458e-06 1.93573e-05
vt 0 1
v 1.61706 -18.3681 -0.0855603
vn 64 7.8458e-06 1.93573e-05
vt 0 1
v 1.58581 -18.3673 -0.0847791
vn -45.2549 -7.12743e-06 45.2548
vt 0 1
v 1.61706 -18.3665 -0.0839978
vn 18.3903 61.3009 3.71213e-06
vt 0 1
v 1.61706 -18.3665 -0.0855603
vn 18.3903 61.3009 3.71213e-06
vt 0 1
v 1.61706 -18.3681 -0.0839978
vn 18.3902 1.14778e-07 61.3009
vt 0 1
v 1.59363 -18.3595 -0.0769666
vn 18.3902 1.14778e-07 61.3009
vt 0 1
v 1.61706 -18.3665 -0.0839978
vn 18.3902 1.14778e-07 61.3009
vt 0 1
v 1.61706 -18.3681 -0.0855603
vn 18.3903 4.39417e-06 -61.3009
vt 0 1
v 1.61706 -18.3665 -0.0855603
vn 18.3903 4.39417e-06 -61.3009
vt 0 1
v 1.59363 -18.3595 -0.0925916
vn 18.3903 4.39417e-06 -61.3009
vt 0 1
v 1.61706 -18.3681 -0.0839978
vn 18.3903 -61.3009 7.41244e-06
vt 0 1
v 1.59363 -18.3751 -0.0769666
vn 18.3903 -61.3009 7.41244e-06
vt 0 1
v 1.61706 -18.3681 -0.0855603
vn 18.3903 -61.3009 7.41244e-06
vt 0 1
v 1.59363 -18.3751 -0.0925916
vn 18.3903 -61.3009 7.41244e-06
vt 0 1
v 1.59363 -18.3751 -0.0769666
vn -45.2549 -7.12743e-06 45.2548
vt 0 1
v 1.59363 -18.3595 -0.0769666
vn -45.2549 -7.12743e-06 45.2548
vt 0 1
v 1.58581 -18.3673 -0.0847791
vn -45.2548 45.2548 -1.50536e-05
vt 0 1
v 1.59363 -18.3595 -0.0769666
vn -45.2548 45.2548 -1.50536e-05
vt 0 1
v 1.59363 -18.3595 -0.0925916
vn -45.2548 45.2548 -1.50536e-05
vt 0 1
v 1.58581 -18.3673 -0.0847791
vn -45.2548 -3.96821e-06 -45.2548
vt 0 1
v 1.59363 -18.3595 -0.0925916
vn -45.2548 -3.96821e-06 -45.2548
vt 0 1
v 1.59363 -18.3751 -0.0925916
vn -45.2548 -3.96821e-06 -45.2548
vt 0 1
v 1.58581 -18.3673 -0.0847791
vn -45.2548 -45.2548 -1.23218e-05
vt 0 1
v 1.59363 -18.3751 -0.0925916
vn -45.2548 -45.2548 -1.23218e-05
vt 0 1
v 1.59363 -18.3751 -0.0769666
vn -45.2548 -45.2548 -1.23218e-05
vt 0 1
fg 1
f 30 31 32
f 27 28 29
f 24 25 26
f 9 22 23
f 21 20 19
f 18 19 20
f 17 16 4
f 15 4 16
f 14 13 12
f 1 12 13
f 11 3 10
f 2 10 3
f 7 6 8
f 5 8 6
mb "Bone06"
m "Bone08"
v 0.145987 -22.4298 -1.95978
vn 64 0 0
vt 0 1
v 0.145987 -22.4298 -1.95978
vn 64 0 0
vt 0 1
v 0.145987 -22.4298 -1.95978
vn 64 0 0
vt 0 1
v 0.145987 -22.4298 -1.95978
vn 64 0 0
vt 0 1
v 0.145987 -23.3574 -2.54559
vn 64 0 0
vt 0 1
v 0.145987 -23.3574 -2.54559
vn 64 0 0
vt 0 1
v 0.145987 -23.3574 -2.54559
vn 64 0 0
vt 0 1
v 0.145987 -23.3574 -2.54559
vn 64 0 0
vt 0 1
v 0.145987 -22.4298 -1.95978
vn 64 0 0
vt 0 1
fg 1
f 9 4 1
f 9 3 4
f 9 2 3
f 9 1 2
f 4 8 1
f 5 1 8
f 3 7 4
f 8 4 7
f 6 2 5
f 1 5 2
f 7 3 6
f 2 6 3
f 7 6 8
f 5 8 6
mb "Bone08"
m "Bone07"
v -0.143666 -23.8999 -1.68185
vn -61.3009 0.0988441 -18.39
vt 0 1
v -0.143666 -23.9156 -1.68194
vn 2.9923e-05 -61.2011 -18.7196
vt 0 1
v -0.128041 -23.9156 -1.68194
vn 2.9923e-05 -61.2011 -18.7196
vt 0 1
v -0.128041 -23.8999 -1.68185
vn 61.3009 0.0989077 -18.39
vt 0 1
v -0.136635 -23.9068 -1.70533
vn 8.66329e-06 0.344098 -63.9991
vt 0 1
v -0.136635 -23.9084 -1.70534
vn 8.66329e-06 0.344098 -63.9991
vt 0 1
v -0.135073 -23.9084 -1.70534
vn 8.66329e-06 0.344098 -63.9991
vt 0 1
v -0.135073 -23.9068 -1.70533
vn 8.66329e-06 0.344098 -63.9991
vt 0 1
v -0.135854 -23.9078 -1.67408
vn -45.2548 -0.243338 45.2542
vt 0 1
v -0.136635 -23.9084 -1.70534
vn 2.9923e-05 -61.2011 -18.7196
vt 0 1
v -0.135073 -23.9084 -1.70534
vn 2.9923e-05 -61.2011 -18.7196
vt 0 1
v -0.136635 -23.9068 -1.70533
vn -61.3009 0.0988441 -18.39
vt 0 1
v -0.143666 -23.9156 -1.68194
vn -61.3009 0.0988441 -18.39
vt 0 1
v -0.136635 -23.9084 -1.70534
vn -61.3009 0.0988441 -18.39
vt 0 1
v -0.135073 -23.9068 -1.70533
vn 61.3009 0.0989077 -18.39
vt 0 1
v -0.135073 -23.9084 -1.70534
vn 61.3009 0.0989077 -18.39
vt 0 1
v -0.128041 -23.9156 -1.68194
vn 61.3009 0.0989077 -18.39
vt 0 1
v -0.136635 -23.9068 -1.70533
vn -2.49442e-05 61.3989 -18.0604
vt 0 1
v -0.143666 -23.8999 -1.68185
vn -2.49442e-05 61.3989 -18.0604
vt 0 1
v -0.135073 -23.9068 -1.70533
vn -2.49442e-05 61.3989 -18.0604
vt 0 1
v -0.128041 -23.8999 -1.68185
vn -2.49442e-05 61.3989 -18.0604
vt 0 1
v -0.143666 -23.8999 -1.68185
vn -45.2548 -0.243338 45.2542
vt 0 1
v -0.143666 -23.9156 -1.68194
vn -45.2548 -0.243338 45.2542
vt 0 1
v -0.135854 -23.9078 -1.67408
vn 1.41267e-05 -45.4975 45.0109
vt 0 1
v -0.143666 -23.9156 -1.68194
vn 1.41267e-05 -45.4975 45.0109
vt 0 1
v -0.128041 -23.9156 -1.68194
vn 1.41267e-05 -45.4975 45.0109
vt 0 1
v -0.135854 -23.9078 -1.67408
vn 45.2548 -0.243291 45.2542
vt 0 1
v -0.128041 -23.9156 -1.68194
vn 45.2548 -0.243291 45.2542
vt 0 1
v -0.128041 -23.8999 -1.68185
vn 45.2548 -0.243291 45.2542
vt 0 1
v -0.135854 -23.9078 -1.67408
vn -2.63785e-05 45.0109 45.4975
vt 0 1
v -0.128041 -23.8999 -1.68185
vn -2.63785e-05 45.0109 45.4975
vt 0 1
v -0.143666 -23.8999 -1.68185
vn -2.63785e-05 45.0109 45.4975
vt 0 1
fg 1
f 30 31 32
f 27 28 29
f 24 25 26
f 9 22 23
f 21 20 19
f 18 19 20
f 17 16 4
f 15 4 16
f 14 13 12
f 1 12 13
f 11 3 10
f 2 10 3
f 7 6 8
f 5 8 6
mb "Bone07"
m "Bone10"
v 0.243109 -21.5223 -0.976478
vn 18.3895 0.162036 61.3009
vt 0 1
v 0.242971 -21.5066 -0.976478
vn 17.8494 61.4605 4.66043e-06
vt 0 1
v 0.242971 -21.5066 -0.992103
vn 17.8494 61.4605 4.66043e-06
vt 0 1
v 0.243109 -21.5223 -0.992103
vn 18.3896 0.162041 -61.3009
vt 0 1
v 0.266484 -21.515 -0.983509
vn 63.9975 0.56391 2.21419e-05
vt 0 1
v 0.26647 -21.5135 -0.983509
vn 63.9975 0.56391 2.21419e-05
vt 0 1
v 0.26647 -21.5135 -0.985072
vn 63.9975 0.56391 2.21419e-05
vt 0 1
v 0.266484 -21.515 -0.985072
vn 63.9975 0.56391 2.21419e-05
vt 0 1
v 0.235228 -21.5145 -0.98429
vn -45.2531 -0.398747 45.2548
vt 0 1
v 0.26647 -21.5135 -0.983509
vn 17.8494 61.4605 4.66043e-06
vt 0 1
v 0.26647 -21.5135 -0.985072
vn 17.8494 61.4605 4.66043e-06
vt 0 1
v 0.266484 -21.515 -0.983509
vn 18.3895 0.162036 61.3009
vt 0 1
v 0.242971 -21.5066 -0.976478
vn 18.3895 0.162036 61.3009
vt 0 1
v 0.26647 -21.5135 -0.983509
vn 18.3895 0.162036 61.3009
vt 0 1
v 0.266484 -21.515 -0.985072
vn 18.3896 0.162041 -61.3009
vt 0 1
v 0.26647 -21.5135 -0.985072
vn 18.3896 0.162041 -61.3009
vt 0 1
v 0.242971 -21.5066 -0.992103
vn 18.3896 0.162041 -61.3009
vt 0 1
v 0.266484 -21.515 -0.983509
vn 18.9296 -61.1365 8.06441e-06
vt 0 1
v 0.243109 -21.5223 -0.976478
vn 18.9296 -61.1365 8.06441e-06
vt 0 1
v 0.266484 -21.515 -0.985072
vn 18.9296 -61.1365 8.06441e-06
vt 0 1
v 0.243109 -21.5223 -0.992103
vn 18.9296 -61.1365 8.06441e-06
vt 0 1
v 0.243109 -21.5223 -0.976478
vn -45.2531 -0.398747 45.2548
vt 0 1
v 0.242971 -21.5066 -0.976478
vn -45.2531 -0.398747 45.2548
vt 0 1
v 0.235228 -21.5145 -0.98429
vn -45.6518 44.8544 -1.69132e-05
vt 0 1
v 0.242971 -21.5066 -0.976478
vn -45.6518 44.8544 -1.69132e-05
vt 0 1
v 0.242971 -21.5066 -0.992103
vn -45.6518 44.8544 -1.69132e-05
vt 0 1
v 0.235228 -21.5145 -0.98429
vn -45.253 -0.398743 -45.2549
vt 0 1
v 0.242971 -21.5066 -0.992103
vn -45.253 -0.398743 -45.2549
vt 0 1
v 0.243109 -21.5223 -0.992103
vn -45.253 -0.398743 -45.2549
vt 0 1
v 0.235228 -21.5145 -0.98429
vn -44.8543 -45.6518 -1.44002e-05
vt 0 1
v 0.243109 -21.5223 -0.992103
vn -44.8543 -45.6518 -1.44002e-05
vt 0 1
v 0.243109 -21.5223 -0.976478
vn -44.8543 -45.6518 -1.44002e-05
vt 0 1
fg 1
f 30 31 32
f 27 28 29
f 24 25 26
f 9 22 23
f 21 20 19
f 18 19 20
f 17 16 4
f 15 4 16
f 14 13 12
f 1 12 13
f 11 3 10
f 2 10 3
f 7 6 8
f 5 8 6
mb "Bone10"
m "Bone13"
v 0.145985 -22.4298 1.79022
vn 64 0 0
vt 0 1
v 0.145985 -22.4298 1.79022
vn 64 0 0
vt 0 1
v 0.145985 -22.4298 1.79022
vn 64 0 0
vt 0 1
v 0.145985 -22.4298 1.79022
vn 64 0 0
vt 0 1
v 0.145986 -23.3574 2.37603
vn 64 0 0
vt 0 1
v 0.145986 -23.3574 2.37603
vn 64 0 0
vt 0 1
v 0.145986 -23.3574 2.37603
vn 64 0 0
vt 0 1
v 0.145986 -23.3574 2.37603
vn 64 0 0
vt 0 1
v 0.145985 -22.4298 1.79022
vn 64 0 0
vt 0 1
fg 1
f 9 4 1
f 9 3 4
f 9 2 3
f 9 1 2
f 4 8 1
f 5 1 8
f 3 7 4
f 8 4 7
f 6 2 5
f 1 5 2
f 7 3 6
f 2 6 3
f 7 6 8
f 5 8 6
mb "Bone13"
m "Bone11"
v 0.43564 -23.8999 1.51229
vn 61.3009 0.0989047 18.39
vt 0 1
v 0.43564 -23.9155 1.51238
vn 9.28197e-06 -61.2011 18.7196
vt 0 1
v 0.420015 -23.9155 1.51238
vn 9.28197e-06 -61.2011 18.7196
vt 0 1
v 0.420015 -23.8999 1.51229
vn -61.3009 0.0988326 18.39
vt 0 1
v 0.428609 -23.9068 1.53577
vn -4.60167e-05 0.344073 63.9991
vt 0 1
v 0.428609 -23.9084 1.53578
vn -4.60167e-05 0.344073 63.9991
vt 0 1
v 0.427046 -23.9084 1.53578
vn -4.60167e-05 0.344073 63.9991
vt 0 1
v 0.427046 -23.9068 1.53577
vn -4.60167e-05 0.344073 63.9991
vt 0 1
v 0.427828 -23.9078 1.50452
vn 45.2549 -0.24327 -45.2542
vt 0 1
v 0.428609 -23.9084 1.53578
vn 9.28197e-06 -61.2011 18.7196
vt 0 1
v 0.427046 -23.9084 1.53578
vn 9.28197e-06 -61.2011 18.7196
vt 0 1
v 0.428609 -23.9068 1.53577
vn 61.3009 0.0989047 18.39
vt 0 1
v 0.43564 -23.9155 1.51238
vn 61.3009 0.0989047 18.39
vt 0 1
v 0.428609 -23.9084 1.53578
vn 61.3009 0.0989047 18.39
vt 0 1
v 0.427046 -23.9068 1.53577
vn -61.3009 0.0988326 18.39
vt 0 1
v 0.427046 -23.9084 1.53578
vn -61.3009 0.0988326 18.39
vt 0 1
v 0.420015 -23.9155 1.51238
vn -61.3009 0.0988326 18.39
vt 0 1
v 0.428609 -23.9068 1.53577
vn -3.57275e-05 61.3989 18.0604
vt 0 1
v 0.43564 -23.8999 1.51229
vn -3.57275e-05 61.3989 18.0604
vt 0 1
v 0.427046 -23.9068 1.53577
vn -3.57275e-05 61.3989 18.0604
vt 0 1
v 0.420015 -23.8999 1.51229
vn -3.57275e-05 61.3989 18.0604
vt 0 1
v 0.43564 -23.8999 1.51229
vn 45.2549 -0.24327 -45.2542
vt 0 1
v 0.43564 -23.9155 1.51238
vn 45.2549 -0.24327 -45.2542
vt 0 1
v 0.427828 -23.9078 1.50452
vn 4.91526e-05 -45.4975 -45.0109
vt 0 1
v 0.43564 -23.9155 1.51238
vn 4.91526e-05 -45.4975 -45.0109
vt 0 1
v 0.420015 -23.9155 1.51238
vn 4.91526e-05 -45.4975 -45.0109
vt 0 1
v 0.427828 -23.9078 1.50452
vn -45.2548 -0.243323 -45.2542
vt 0 1
v 0.420015 -23.9155 1.51238
vn -45.2548 -0.243323 -45.2542
vt 0 1
v 0.420015 -23.8999 1.51229
vn -45.2548 -0.243323 -45.2542
vt 0 1
v 0.427828 -23.9078 1.50452
vn 1.59247e-05 45.0109 -45.4975
vt 0 1
v 0.420015 -23.8999 1.51229
vn 1.59247e-05 45.0109 -45.4975
vt 0 1
v 0.43564 -23.8999 1.51229
vn 1.59247e-05 45.0109 -45.4975
vt 0 1
fg 1
f 30 31 32
f 27 28 29
f 24 25 26
f 9 22 23
f 21 20 19
f 18 19 20
f 17 16 4
f 15 4 16
f 14 13 12
f 1 12 13
f 11 3 10
f 2 10 3
f 7 6 8
f 5 8 6
mb "Bone11"
m "Bone12"
v 0.243108 -21.5223 0.822544
vn 18.3895 0.162036 61.3009
vt 0 1
v 0.242971 -21.5066 0.822544
vn 17.8494 61.4605 4.66043e-06
vt 0 1
v 0.242971 -21.5066 0.806919
vn 17.8494 61.4605 4.66043e-06
vt 0 1
v 0.243108 -21.5223 0.806919
vn 18.3896 0.162041 -61.3009
vt 0 1
v 0.266483 -21.515 0.815513
vn 63.9975 0.56391 2.21419e-05
vt 0 1
v 0.266469 -21.5135 0.815513
vn 63.9975 0.56391 2.21419e-05
vt 0 1
v 0.266469 -21.5135 0.81395
vn 63.9975 0.56391 2.21419e-05
vt 0 1
v 0.266483 -21.515 0.81395
vn 63.9975 0.56391 2.21419e-05
vt 0 1
v 0.235227 -21.5145 0.814732
vn -45.2531 -0.398747 45.2548
vt 0 1
v 0.266469 -21.5135 0.815513
vn 17.8494 61.4605 4.66043e-06
vt 0 1
v 0.266469 -21.5135 0.81395
vn 17.8494 61.4605 4.66043e-06
vt 0 1
v 0.266483 -21.515 0.815513
vn 18.3895 0.162036 61.3009
vt 0 1
v 0.242971 -21.5066 0.822544
vn 18.3895 0.162036 61.3009
vt 0 1
v 0.266469 -21.5135 0.815513
vn 18.3895 0.162036 61.3009
vt 0 1
v 0.266483 -21.515 0.81395
vn 18.3896 0.162041 -61.3009
vt 0 1
v 0.266469 -21.5135 0.81395
vn 18.3896 0.162041 -61.3009
vt 0 1
v 0.242971 -21.5066 0.806919
vn 18.3896 0.162041 -61.3009
vt 0 1
v 0.266483 -21.515 0.815513
vn 18.9296 -61.1365 8.06441e-06
vt 0 1
v 0.243108 -21.5223 0.822544
vn 18.9296 -61.1365 8.06441e-06
vt 0 1
v 0.266483 -21.515 0.81395
vn 18.9296 -61.1365 8.06441e-06
vt 0 1
v 0.243108 -21.5223 0.806919
vn 18.9296 -61.1365 8.06441e-06
vt 0 1
v 0.243108 -21.5223 0.822544
vn -45.2531 -0.398747 45.2548
vt 0 1
v 0.242971 -21.5066 0.822544
vn -45.2531 -0.398747 45.2548
vt 0 1
v 0.235227 -21.5145 0.814732
vn -45.6518 44.8544 -1.69132e-05
vt 0 1
v 0.242971 -21.5066 0.822544
vn -45.6518 44.8544 -1.69132e-05
vt 0 1
v 0.242971 -21.5066 0.806919
vn -45.6518 44.8544 -1.69132e-05
vt 0 1
v 0.235227 -21.5145 0.814732
vn -45.253 -0.398743 -45.2549
vt 0 1
v 0.242971 -21.5066 0.806919
vn -45.253 -0.398743 -45.2549
vt 0 1
v 0.243108 -21.5223 0.806919
vn -45.253 -0.398743 -45.2549
vt 0 1
v 0.235227 -21.5145 0.814732
vn -44.8543 -45.6518 -1.44002e-05
vt 0 1
v 0.243108 -21.5223 0.806919
vn -44.8543 -45.6518 -1.44002e-05
vt 0 1
v 0.243108 -21.5223 0.822544
vn -44.8543 -45.6518 -1.44002e-05
vt 0 1
fg 1
f 30 31 32
f 27 28 29
f 24 25 26
f 9 22 23
f 21 20 19
f 18 19 20
f 17 16 4
f 15 4 16
f 14 13 12
f 1 12 13
f 11 3 10
f 2 10 3
f 7 6 8
f 5 8 6
mb "Bone12"
m "Bone04"
v 1.76489 -18.1277 -0.879965
vn 64 0 0
vt 0 1
v 1.76489 -18.1277 -0.879965
vn 64 0 0
vt 0 1
v 1.76489 -18.1277 -0.879965
vn 64 0 0
vt 0 1
v 1.76489 -18.1277 -0.879965
vn 64 0 0
vt 0 1
v 1.76552 -18.162 -0.879763
vn 64 0 0
vt 0 1
v 1.76552 -18.162 -0.879763
vn 64 0 0
vt 0 1
v 1.76552 -18.162 -0.879763
vn 64 0 0
vt 0 1
v 1.76552 -18.162 -0.879763
vn 64 0 0
vt 0 1
v 1.76489 -18.1277 -0.879965
vn 64 0 0
vt 0 1
fg 1
f 9 4 1
f 9 3 4
f 9 2 3
f 9 1 2
f 4 8 1
f 5 1 8
f 3 7 4
f 8 4 7
f 6 2 5
f 1 5 2
f 7 3 6
f 2 6 3
f 7 6 8
f 5 8 6
mb "Bone04"
m "Bone24"
v 1.85594 -18.107 -0.875574
vn 3.02022 -2.92929 63.8615
vt 0 1
v 1.85605 -18.1069 -0.875574
vn 55.5446 31.5257 4.1151
vt 0 1
v 1.85608 -18.1069 -0.875727
vn 55.5446 31.5257 4.1151
vt 0 1
v 1.85597 -18.107 -0.875727
vn 22.7128 -22.028 -55.6318
vt 0 1
v 1.85617 -18.1071 -0.87559
vn 44.7772 -43.4274 14.3201
vt 0 1
v 1.85618 -18.1071 -0.87559
vn 44.7772 -43.4274 14.3201
vt 0 1
v 1.85618 -18.1071 -0.875606
vn 44.7772 -43.4274 14.3201
vt 0 1
v 1.85617 -18.1071 -0.875606
vn 44.7772 -43.4274 14.3201
vt 0 1
v 1.85595 -18.1069 -0.875668
vn -38.931 37.7574 33.9817
vt 0 1
v 1.85618 -18.1071 -0.87559
vn 55.5446 31.5257 4.1151
vt 0 1
v 1.85618 -18.1071 -0.875606
vn 55.5446 31.5257 4.1151
vt 0 1
v 1.85617 -18.1071 -0.87559
vn 3.02022 -2.92929 63.8615
vt 0 1
v 1.85605 -18.1069 -0.875574
vn 3.02022 -2.92929 63.8615
vt 0 1
v 1.85618 -18.1071 -0.87559
vn 3.02022 -2.92929 63.8615
vt 0 1
v 1.85617 -18.1071 -0.875606
vn 22.7128 -22.028 -55.6318
vt 0 1
v 1.85618 -18.1071 -0.875606
vn 22.7128 -22.028 -55.6318
vt 0 1
v 1.85608 -18.1069 -0.875727
vn 22.7128 -22.028 -55.6318
vt 0 1
v 1.85617 -18.1071 -0.87559
vn -29.8118 -56.483 4.11449
vt 0 1
v 1.85594 -18.107 -0.875574
vn -29.8118 -56.483 4.11449
vt 0 1
v 1.85617 -18.1071 -0.875606
vn -29.8118 -56.483 4.11449
vt 0 1
v 1.85597 -18.107 -0.875727
vn -29.8118 -56.483 4.11449
vt 0 1
v 1.85594 -18.107 -0.875574
vn -38.931 37.7574 33.9817
vt 0 1
v 1.85605 -18.1069 -0.875574
vn -38.931 37.7574 33.9817
vt 0 1
v 1.85595 -18.1069 -0.875668
vn -0.15505 63.1937 -10.1255
vt 0 1
v 1.85605 -18.1069 -0.875574
vn -0.15505 63.1937 -10.1255
vt 0 1
v 1.85608 -18.1069 -0.875727
vn -0.15505 63.1937 -10.1255
vt 0 1
v 1.85595 -18.1069 -0.875668
vn -24.3932 23.658 -54.2335
vt 0 1
v 1.85608 -18.1069 -0.875727
vn -24.3932 23.658 -54.2335
vt 0 1
v 1.85597 -18.107 -0.875727
vn -24.3932 23.658 -54.2335
vt 0 1
v 1.85595 -18.1069 -0.875668
vn -63.1688 -1.77836 -10.126
vt 0 1
v 1.85597 -18.107 -0.875727
vn -63.1688 -1.77836 -10.126
vt 0 1
v 1.85594 -18.107 -0.875574
vn -63.1688 -1.77836 -10.126
vt 0 1
fg 1
f 30 31 32
f 27 28 29
f 24 25 26
f 9 22 23
f 21 20 19
f 18 19 20
f 17 16 4
f 15 4 16
f 14 13 12
f 1 12 13
f 11 3 10
f 2 10 3
f 7 6 8
f 5 8 6
mb "Bone24"
m "Bone25"
v 1.76489 -18.1277 0.710407
vn 64 0 0
vt 0 1
v 1.76489 -18.1277 0.710407
vn 64 0 0
vt 0 1
v 1.76489 -18.1277 0.710407
vn 64 0 0
vt 0 1
v 1.76489 -18.1277 0.710407
vn 64 0 0
vt 0 1
v 1.76635 -18.1716 0.70994
vn 64 0 0
vt 0 1
v 1.76635 -18.1716 0.70994
vn 64 0 0
vt 0 1
v 1.76635 -18.1716 0.70994
vn 64 0 0
vt 0 1
v 1.76635 -18.1716 0.70994
vn 64 0 0
vt 0 1
v 1.76489 -18.1277 0.710407
vn 64 0 0
vt 0 1
fg 1
f 9 4 1
f 9 3 4
f 9 2 3
f 9 1 2
f 4 8 1
f 5 1 8
f 3 7 4
f 8 4 7
f 6 2 5
f 1 5 2
f 7 3 6
f 2 6 3
f 7 6 8
f 5 8 6
mb "Bone25"
m "Bone26"
v 1.76864 -18.1009 0.710234
vn -3.02348 0.0944439 63.9285
vt 0 1
v 1.76864 -18.1011 0.710234
vn -63.8145 -1.16643 4.72753
vt 0 1
v 1.76864 -18.101 0.710227
vn -63.8145 -1.16643 4.72753
vt 0 1
v 1.76864 -18.1009 0.710227
vn -24.1893 0.755498 -59.2478
vt 0 1
v 1.76863 -18.1008 0.710233
vn -60.9315 1.90309 19.4867
vt 0 1
v 1.76863 -18.1008 0.710233
vn -60.9315 1.90309 19.4867
vt 0 1
v 1.76863 -18.1008 0.710232
vn -60.9315 1.90309 19.4867
vt 0 1
v 1.76863 -18.1008 0.710232
vn -60.9315 1.90309 19.4867
vt 0 1
v 1.76864 -18.101 0.71023
vn 48.2027 -1.50552 42.0741
vt 0 1
v 1.76863 -18.1008 0.710233
vn -63.8145 -1.16643 4.72753
vt 0 1
v 1.76863 -18.1008 0.710232
vn -63.8145 -1.16643 4.72753
vt 0 1
v 1.76863 -18.1008 0.710233
vn -3.02348 0.0944439 63.9285
vt 0 1
v 1.76864 -18.1011 0.710234
vn -3.02348 0.0944439 63.9285
vt 0 1
v 1.76863 -18.1008 0.710233
vn -3.02348 0.0944439 63.9285
vt 0 1
v 1.76863 -18.1008 0.710232
vn -24.1893 0.755498 -59.2478
vt 0 1
v 1.76863 -18.1008 0.710232
vn -24.1893 0.755498 -59.2478
vt 0 1
v 1.76864 -18.101 0.710227
vn -24.1893 0.755498 -59.2478
vt 0 1
v 1.76863 -18.1008 0.710233
vn 63.2834 3.86139 8.73532
vt 0 1
v 1.76864 -18.1009 0.710234
vn 63.2834 3.86139 8.73532
vt 0 1
v 1.76863 -18.1008 0.710232
vn 63.2834 3.86139 8.73532
vt 0 1
v 1.76864 -18.1009 0.710227
vn 63.2834 3.86139 8.73532
vt 0 1
v 1.76864 -18.1009 0.710234
vn 48.2027 -1.50552 42.0741
vt 0 1
v 1.76864 -18.1011 0.710234
vn 48.2027 -1.50552 42.0741
vt 0 1
v 1.76864 -18.101 0.71023
vn 0.965514 -12.6089 -62.7382
vt 0 1
v 1.76864 -18.1011 0.710234
vn 0.965514 -12.6089 -62.7382
vt 0 1
v 1.76864 -18.101 0.710227
vn 0.965514 -12.6089 -62.7382
vt 0 1
v 1.76864 -18.101 0.71023
vn 26.2507 -0.819902 -58.3629
vt 0 1
v 1.76864 -18.101 0.710227
vn 26.2507 -0.819902 -58.3629
vt 0 1
v 1.76864 -18.1009 0.710227
vn 26.2507 -0.819902 -58.3629
vt 0 1
v 1.76864 -18.101 0.71023
vn 63.1932 0.0572917 -10.1299
vt 0 1
v 1.76864 -18.1009 0.710227
vn 63.1932 0.0572917 -10.1299
vt 0 1
v 1.76864 -18.1009 0.710234
vn 63.1932 0.0572917 -10.1299
vt 0 1
fg 1
f 30 31 32
f 27 28 29
f 24 25 26
f 9 22 23
f 21 20 19
f 18 19 20
f 17 16 4
f 15 4 16
f 14 13 12
f 1 12 13
f 11 3 10
f 2 10 3
f 7 6 8
f 5 8 6
mb "Bone26"
md "Bone02"
b "Bone02" 0 1 0 3.57628e-07 0 1 0 -3.57628e-07 0 1 0.164174 -21.4439 -2.04972
m "Bone02"
v 0.171987 -21.4517 -2.04191
vn 18.3902 0 61.3009
vt 0 1
v 0.171987 -21.4361 -2.04191
vn 18.3903 61.3009 6.57687e-06
vt 0 1
v 0.171987 -21.4361 -2.05753
vn 18.3903 61.3009 6.57687e-06
vt 0 1
v 0.171987 -21.4517 -2.05753
vn 18.3903 0 -61.3009
vt 0 1
v 0.195424 -21.4447 -2.04894
vn 64 0 2.28882e-05
vt 0 1
v 0.195424 -21.4431 -2.04894
vn 64 0 2.28882e-05
vt 0 1
v 0.195424 -21.4431 -2.0505
vn 64 0 2.28882e-05
vt 0 1
v 0.195424 -21.4447 -2.0505
vn 64 0 2.28882e-05
vt 0 1
v 0.164174 -21.4439 -2.04972
vn -45.2548 0 45.2548
vt 0 1
v 0.195424 -21.4431 -2.04894
vn 18.3903 61.3009 6.57687e-06
vt 0 1
v 0.195424 -21.4431 -2.0505
vn 18.3903 61.3009 6.57687e-06
vt 0 1
v 0.195424 -21.4447 -2.04894
vn 18.3902 0 61.3009
vt 0 1
v 0.171987 -21.4361 -2.04191
vn 18.3902 0 61.3009
vt 0 1
v 0.195424 -21.4431 -2.04894
vn 18.3902 0 61.3009
vt 0 1
v 0.195424 -21.4447 -2.0505
vn 18.3903 0 -61.3009
vt 0 1
v 0.195424 -21.4431 -2.0505
vn 18.3903 0 -61.3009
vt 0 1
v 0.171987 -21.4361 -2.05753
vn 18.3903 0 -61.3009
vt 0 1
v 0.195424 -21.4447 -2.04894
vn 18.3903 -61.3009 6.57687e-06
vt 0 1
v 0.171987 -21.4517 -2.04191
vn 18.3903 -61.3009 6.57687e-06
vt 0 1
v 0.195424 -21.4447 -2.0505
vn 18.3903 -61.3009 6.57687e-06
vt 0 1
v 0.171987 -21.4517 -2.05753
vn 18.3903 -61.3009 6.57687e-06
vt 0 1
v 0.171987 -21.4517 -2.04191
vn -45.2548 0 45.2548
vt 0 1
v 0.171987 -21.4361 -2.04191
vn -45.2548 0 45.2548
vt 0 1
v 0.164174 -21.4439 -2.04972
vn -45.2548 45.2548 -1.61844e-05
vt 0 1
v 0.171987 -21.4361 -2.04191
vn -45.2548 45.2548 -1.61844e-05
vt 0 1
v 0.171987 -21.4361 -2.05753
vn -45.2548 45.2548 -1.61844e-05
vt 0 1
v 0.164174 -21.4439 -2.04972
vn -45.2548 0 -45.2548
vt 0 1
v 0.171987 -21.4361 -2.05753
vn -45.2548 0 -45.2548
vt 0 1
v 0.171987 -21.4517 -2.05753
vn -45.2548 0 -45.2548
vt 0 1
v 0.164174 -21.4439 -2.04972
vn -45.2548 -45.2548 -1.61844e-05
vt 0 1
v 0.171987 -21.4517 -2.05753
vn -45.2548 -45.2548 -1.61844e-05
vt 0 1
v 0.171987 -21.4517 -2.04191
vn -45.2548 -45.2548 -1.61844e-05
vt 0 1
fg 1
f 30 31 32
f 27 28 29
f 24 25 26
f 9 22 23
f 21 20 19
f 18 19 20
f 17 16 4
f 15 4 16
f 14 13 12
f 1 12 13
f 11 3 10
f 2 10 3
f 7 6 8
f 5 8 6
mb "Bone02"


--- import to scene ---
gx_importer.import()
