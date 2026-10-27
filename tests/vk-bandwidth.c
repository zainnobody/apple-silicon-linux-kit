// Vulkan read bandwidth: timed dispatches read a large buffer (vk-bandwidth.comp), the host checks
// the sum of one run and prints GB/s. Build with tests/build-tests.sh.
// Usage: vk-bandwidth [MiB] [repeats] [per_thread]   (VK_BANDWIDTH_CACHED=0|1 picks the memory type)
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <vulkan/vulkan.h>

#define CHECK(x) do { VkResult r_ = (x); if (r_ != VK_SUCCESS) { \
	fprintf(stderr, "%s failed: %d\nVK_BANDWIDTH_FAIL\n", #x, r_); exit(1); } } while (0)

static VkDevice dev;
static VkPhysicalDevice phys;

static double now(void)
{
	struct timespec t;
	clock_gettime(CLOCK_MONOTONIC, &t);
	return t.tv_sec + t.tv_nsec * 1e-9;
}

static VkBuffer make_buffer(VkDeviceSize size, VkDeviceMemory *mem, void **map)
{
	VkBufferCreateInfo bci = { .sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO, .size = size,
		.usage = VK_BUFFER_USAGE_STORAGE_BUFFER_BIT };
	VkBuffer buf;
	CHECK(vkCreateBuffer(dev, &bci, NULL, &buf));
	VkMemoryRequirements req;
	vkGetBufferMemoryRequirements(dev, buf, &req);
	VkPhysicalDeviceMemoryProperties mp;
	vkGetPhysicalDeviceMemoryProperties(phys, &mp);
	VkMemoryPropertyFlags want = VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT | VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT;
	/* VK_BANDWIDTH_CACHED=0 picks a type without HOST_CACHED (write-combined on Apple GPUs). */
	const char *cached_env = getenv("VK_BANDWIDTH_CACHED");
	int cached = cached_env ? atoi(cached_env) : -1;
	uint32_t type = UINT32_MAX;
	for (uint32_t i = 0; i < mp.memoryTypeCount; i++) {
		VkMemoryPropertyFlags fl = mp.memoryTypes[i].propertyFlags;
		if (!(req.memoryTypeBits & (1u << i)) || (fl & want) != want)
			continue;
		if (cached >= 0 && !!(fl & VK_MEMORY_PROPERTY_HOST_CACHED_BIT) != cached)
			continue;
		type = i;
		break;
	}
	if (type == UINT32_MAX) { fprintf(stderr, "no matching memory type\nVK_BANDWIDTH_FAIL\n"); exit(1); }
	VkMemoryAllocateInfo mai = { .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
		.allocationSize = req.size, .memoryTypeIndex = type };
	CHECK(vkAllocateMemory(dev, &mai, NULL, mem));
	CHECK(vkBindBufferMemory(dev, buf, *mem, 0));
	CHECK(vkMapMemory(dev, *mem, 0, size, 0, map));
	return buf;
}

int main(int argc, char **argv)
{
	uint32_t mib = argc > 1 ? (uint32_t)atoi(argv[1]) : 256;
	uint32_t repeats = argc > 2 ? (uint32_t)atoi(argv[2]) : 20;
	uint32_t per_thread = argc > 3 ? (uint32_t)atoi(argv[3]) : 16;
	const char *spv = getenv("VK_BANDWIDTH_SPV") ? getenv("VK_BANDWIDTH_SPV") : "vk-bandwidth.spv";
	uint32_t total = mib * 1024u * 1024u / 16u;                 /* uvec4 elements */
	uint32_t threads = (total + per_thread - 1) / per_thread;
	uint32_t groups = (threads + 255) / 256;
	threads = groups * 256;

	VkApplicationInfo app = { .sType = VK_STRUCTURE_TYPE_APPLICATION_INFO, .apiVersion = VK_API_VERSION_1_1 };
	VkInstanceCreateInfo ici = { .sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO, .pApplicationInfo = &app };
	VkInstance instance;
	CHECK(vkCreateInstance(&ici, NULL, &instance));
	uint32_t ndev = 1;
	vkEnumeratePhysicalDevices(instance, &ndev, &phys);
	if (!ndev) { fprintf(stderr, "no device\nVK_BANDWIDTH_FAIL\n"); return 1; }
	VkPhysicalDeviceProperties props;
	vkGetPhysicalDeviceProperties(phys, &props);
	printf("device: %s\n", props.deviceName);

	float prio = 1.0f;
	VkDeviceQueueCreateInfo qci = { .sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
		.queueFamilyIndex = 0, .queueCount = 1, .pQueuePriorities = &prio };
	VkDeviceCreateInfo dci = { .sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
		.queueCreateInfoCount = 1, .pQueueCreateInfos = &qci };
	CHECK(vkCreateDevice(phys, &dci, NULL, &dev));
	VkQueue queue;
	vkGetDeviceQueue(dev, 0, 0, &queue);

	VkDeviceMemory in_mem, out_mem;
	uint32_t *in_map, *out_map;
	VkBuffer in_buf = make_buffer((VkDeviceSize)total * 16, &in_mem, (void **)&in_map);
	VkBuffer out_buf = make_buffer((VkDeviceSize)threads * 4, &out_mem, (void **)&out_map);
	uint64_t expect = 0;
	for (uint64_t i = 0; i < (uint64_t)total * 4; i++) { in_map[i] = (uint32_t)(i * 2654435761u) >> 8; expect += in_map[i]; }

	FILE *f = fopen(spv, "rb");
	if (!f) { perror(spv); return 1; }
	fseek(f, 0, SEEK_END);
	size_t spv_size = (size_t)ftell(f);
	rewind(f);
	uint32_t *code = malloc(spv_size);
	if (fread(code, 1, spv_size, f) != spv_size) return 1;
	fclose(f);
	VkShaderModuleCreateInfo smci = { .sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
		.codeSize = spv_size, .pCode = code };
	VkShaderModule module;
	CHECK(vkCreateShaderModule(dev, &smci, NULL, &module));

	VkDescriptorSetLayoutBinding b[2] = {
		{ .binding = 0, .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .descriptorCount = 1, .stageFlags = VK_SHADER_STAGE_COMPUTE_BIT },
		{ .binding = 1, .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .descriptorCount = 1, .stageFlags = VK_SHADER_STAGE_COMPUTE_BIT },
	};
	VkDescriptorSetLayoutCreateInfo dslci = { .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		.bindingCount = 2, .pBindings = b };
	VkDescriptorSetLayout dsl;
	CHECK(vkCreateDescriptorSetLayout(dev, &dslci, NULL, &dsl));
	VkPushConstantRange pcr = { .stageFlags = VK_SHADER_STAGE_COMPUTE_BIT, .size = 8 };
	VkPipelineLayoutCreateInfo plci = { .sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
		.setLayoutCount = 1, .pSetLayouts = &dsl, .pushConstantRangeCount = 1, .pPushConstantRanges = &pcr };
	VkPipelineLayout layout;
	CHECK(vkCreatePipelineLayout(dev, &plci, NULL, &layout));
	VkComputePipelineCreateInfo cpci = { .sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
		.stage = { .sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
			.stage = VK_SHADER_STAGE_COMPUTE_BIT, .module = module, .pName = "main" },
		.layout = layout };
	VkPipeline pipeline;
	CHECK(vkCreateComputePipelines(dev, VK_NULL_HANDLE, 1, &cpci, NULL, &pipeline));

	VkDescriptorPoolSize ps = { .type = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .descriptorCount = 2 };
	VkDescriptorPoolCreateInfo dpci = { .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
		.maxSets = 1, .poolSizeCount = 1, .pPoolSizes = &ps };
	VkDescriptorPool pool;
	CHECK(vkCreateDescriptorPool(dev, &dpci, NULL, &pool));
	VkDescriptorSetAllocateInfo dsai = { .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
		.descriptorPool = pool, .descriptorSetCount = 1, .pSetLayouts = &dsl };
	VkDescriptorSet set;
	CHECK(vkAllocateDescriptorSets(dev, &dsai, &set));
	VkDescriptorBufferInfo dbi[2] = { { .buffer = in_buf, .range = VK_WHOLE_SIZE }, { .buffer = out_buf, .range = VK_WHOLE_SIZE } };
	VkWriteDescriptorSet wds[2] = {
		{ .sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = set, .dstBinding = 0, .descriptorCount = 1,
		  .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .pBufferInfo = &dbi[0] },
		{ .sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = set, .dstBinding = 1, .descriptorCount = 1,
		  .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .pBufferInfo = &dbi[1] },
	};
	vkUpdateDescriptorSets(dev, 2, wds, 0, NULL);

	VkCommandPoolCreateInfo cpi = { .sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO, .queueFamilyIndex = 0 };
	VkCommandPool cpool;
	CHECK(vkCreateCommandPool(dev, &cpi, NULL, &cpool));
	VkCommandBufferAllocateInfo cbai = { .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
		.commandPool = cpool, .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY, .commandBufferCount = 1 };
	VkCommandBuffer cb;
	CHECK(vkAllocateCommandBuffers(dev, &cbai, &cb));
	VkFenceCreateInfo fci = { .sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO };
	VkFence fence;
	CHECK(vkCreateFence(dev, &fci, NULL, &fence));
	uint32_t push[2] = { total, per_thread };

	/* One run per submit: the first is a warm-up and the correctness check. */
	double best = 1e9, sum = 0;
	for (uint32_t r = 0; r <= repeats; r++) {
		VkCommandBufferBeginInfo cbbi = { .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO };
		CHECK(vkBeginCommandBuffer(cb, &cbbi));
		vkCmdBindPipeline(cb, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline);
		vkCmdBindDescriptorSets(cb, VK_PIPELINE_BIND_POINT_COMPUTE, layout, 0, 1, &set, 0, NULL);
		vkCmdPushConstants(cb, layout, VK_SHADER_STAGE_COMPUTE_BIT, 0, 8, push);
		vkCmdDispatch(cb, groups, 1, 1);
		VkMemoryBarrier mb = { .sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER,
			.srcAccessMask = VK_ACCESS_SHADER_WRITE_BIT, .dstAccessMask = VK_ACCESS_HOST_READ_BIT };
		vkCmdPipelineBarrier(cb, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_PIPELINE_STAGE_HOST_BIT, 0, 1, &mb, 0, NULL, 0, NULL);
		CHECK(vkEndCommandBuffer(cb));
		VkSubmitInfo si = { .sType = VK_STRUCTURE_TYPE_SUBMIT_INFO, .commandBufferCount = 1, .pCommandBuffers = &cb };
		double t0 = now();
		CHECK(vkQueueSubmit(queue, 1, &si, fence));
		CHECK(vkWaitForFences(dev, 1, &fence, VK_TRUE, 10ull * 1000 * 1000 * 1000));
		double dt = now() - t0;
		CHECK(vkResetFences(dev, 1, &fence));
		CHECK(vkResetCommandBuffer(cb, 0));
		if (r == 0) {
			uint64_t got = 0;
			uint32_t check = 0;
			for (uint32_t i = 0; i < threads; i++) got += out_map[i];
			/* The shader sums in 32 bits per lane, so compare modulo 2^32. */
			check = (uint32_t)got == (uint32_t)expect;
			if (!check) { printf("sum mismatch\nVK_BANDWIDTH_FAIL\n"); return 1; }
			continue;
		}
		sum += dt;
		if (dt < best) best = dt;
	}
	double bytes = (double)total * 16;
	printf("%u MiB, %u threads x %u reads, %u runs: best %.1f GB/s, mean %.1f GB/s (submit and wait included)\nVK_BANDWIDTH_PASS\n",
	       mib, threads, per_thread, repeats, bytes / best / 1e9, bytes / (sum / repeats) / 1e9);
	return 0;
}
