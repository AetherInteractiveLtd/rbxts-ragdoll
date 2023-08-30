local Players = game:GetService("Players")
--[[
	Constructs ragdoll constraints and flags some limbs so they can't collide with each other
	for stability purposes. After this is finished, it tags the humanoid so the client/server
	ragdoll scripts can listen to StateChanged and disable/enable the rigid Motor6D joints when
	the humanoid enters valid ragdoll states
--]]

local buildConstraints = require(script:WaitForChild("buildConstraints"))
local buildCollisionFilters = require(script:WaitForChild("buildCollisionFilters"))

--[[
	 Builds a map that allows us to find Attachment0/Attachment1 when we have the other,
		and keep track of the joint that connects them. Format is
		{
			["WaistRigAttachment"] = {
				Joint = UpperTorso.Waist<Motor6D>,
				Attachment0 = LowerTorso.WaistRigAttachment<Attachment>,
				Attachment1 = UpperToros.WaistRigAttachment<Attachment>,
			},
			...
		}
--]]
local function buildAttachmentMap(character)
	local attachmentMap = {}

	-- NOTE: GetConnectedParts doesn't work until parts have been parented to Workspace, so
	-- we can't use it (unless we want to have that silly restriction for creating ragdolls)
	for _, part in pairs(character:GetChildren()) do
		if not part:IsA("BasePart") then continue end

		for _, attachment in pairs(part:GetChildren()) do
			if not attachment:IsA("Attachment") then continue end

			local jointName = attachment.Name:match("^(.+)RigAttachment$")
			local joint = jointName and attachment.Parent:FindFirstChild(jointName) or nil

			if not joint then continue end

			local Attachment0 = joint.Part0:WaitForChild(attachment.Name,1);
			local Attachment1 = joint.Part1:WaitForChild(attachment.Name,1);

			if not Attachment0 or not Attachment1 then
				local missing = ""
				if not Attachment0 then missing ..= "0" end
				if not Attachment1 then missing ..= "1" end
				-- print("THESE ATTACHMENTS WERE NOT FOUND:",attachment.Name,missing)
				continue
			end

			attachmentMap[attachment.Name] = {
				Joint = joint,
				Attachment0 = Attachment0;
				Attachment1 = Attachment1;
			}
		end
	end

	return attachmentMap
end

local function BeginBuildRagdoll(humanoid: Humanoid, character)
	-- Trying to recover from broken joints is not fun. It's impossible to reattach things like
	-- armor and tools in a generic way that works across all games, so we just prevent that
	-- from happening in the first place.
	humanoid.BreakJointsOnDeath = false

	-- Roblox decided to make the ghost HumanoidRootPart CanCollide=true for some reason, so
	-- we correct this and disable collisions. This prevents the invisible part from colliding
	-- with the world and ruining the physics simulation (e.g preventing a roundish torso from
	-- rolling)
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if rootPart then
		rootPart.CanCollide = false
	end

	local attachmentMap = buildAttachmentMap(character)
	local ragdollConstraints = buildConstraints(attachmentMap)
	local collisionFilters = buildCollisionFilters(attachmentMap, character.PrimaryPart)

	collisionFilters.Parent = ragdollConstraints
	ragdollConstraints.Parent = character
end

return function(humanoid)
	local character = humanoid.Parent
	local player = Players:GetPlayerFromCharacter(character)

	if player and not player:HasAppearanceLoaded() then
		local thread
		local connection = player.CharacterAppearanceLoaded:Once(function()
			BeginBuildRagdoll(humanoid, character)
			
			if not coroutine.status(thread) == "running" then
				coroutine.close(thread)
			end
		end)
		
		thread = task.delay(5, function()
			connection:Disconnect()
		end)
	else
		task.defer(function()
			BeginBuildRagdoll(humanoid, character)
		end)
	end
end
