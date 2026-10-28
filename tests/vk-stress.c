// GPU stress test as a Vulkan compute kernel: the same math and loop as tests/metal-stress.swift,
// so Linux and macOS compare the same shader type. Each frame is one dispatch over 1024x1024
// (16x16 groups, 400 xorshift steps per pixel, new seed per frame). Frames are submitted without
// waiting; every 10th frame is waited for and every 7th pixel is checked against the CPU.
// Build with tests/build-tests.sh. Usage: vk-stress <seconds>   (needs vk-stress.spv in the
// current folder, or VK_STRESS_SPV). VK_STRESS_CHECK_EVERY=n waits and checks every n-th frame
// (default 10, as in metal-stress; 0 never waits, so the GPU never idles).
// VK_STRESS_REPORT_S=n prints the frame rate of each n-second step (default 30).
// VK_STRESS_PAUSE=a:b waits for the queue at a seconds and sleeps b seconds (one idle gap in the
// same process and GPU context), then goes on; the pause does not count in the totals.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <vulkan/vulkan.h>

#define W 1024
#define H 1024
#define ITERS 400
#define RING 10

#define CHECK(x) do { VkResult r_ = (x); if (r_ != VK_SUCCESS) { \
	fprintf(stderr, "%s failed: %d\nSTRESS_FAIL\n", #x, r_); exit(1); } } while (0)

static unsigned cpu_value(unsigned x, unsigned y, unsigned seed)
{
	unsigned s = (x * 73856093u) ^ (y * 19349663u) ^ seed;
	for (int i = 0; i < ITERS; i++) {
		s ^= s << 13;
		s ^= s >> 17;
		s ^= s << 5;
		s += (unsigned)i;
	}
	return s;
}

static double now(void)
{
	struct timespec t;
	clock_gettime(CLOCK_MONOTONIC, &t);
	return t.tv_sec + t.tv_nsec / 1e9;
}

static unsigned char *read_file(const char *path, size_t *size)
{
	FILE *f = fopen(path, "rb");
	if (!f) { perror(path); exit(1); }
	fseek(f, 0, SEEK_END);
	*size = (size_t)ftell(f);
	rewind(f);
	unsigned char *data = malloc(*size);
	if (fread(data, 1, *size, f) != *size) { perror("fread"); exit(1); }
	fclose(f);
	return data;
}

int main(int argc, char **argv)
{
	double seconds = argc > 1 ? atof(argv[1]) : 60;
	const char *spv = getenv("VK_STRESS_SPV") ? getenv("VK_STRESS_SPV") : "vk-stress.spv";
	long check_every = getenv("VK_STRESS_CHECK_EVERY") ? atol(getenv("VK_STRESS_CHECK_EVERY")) : 10;

	VkApplicationInfo app = { .sType = VK_STRUCTURE_TYPE_APPLICATION_INFO, .apiVersion = VK_API_VERSION_1_1 };
	VkInstanceCreateInfo ici = { .sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO, .pApplicationInfo = &app };
	VkInstance instance;
	CHECK(vkCreateInstance(&ici, NULL, &instance));

	uint32_t ndev = 8;
	VkPhysicalDevice devs[8];
	CHECK(vkEnumeratePhysicalDevices(instance, &ndev, devs));
	VkPhysicalDevice phys = VK_NULL_HANDLE;
	for (uint32_t i = 0; i < ndev; i++) {
		VkPhysicalDeviceProperties p;
		vkGetPhysicalDeviceProperties(devs[i], &p);
		if (p.deviceType != VK_PHYSICAL_DEVICE_TYPE_CPU) { phys = devs[i]; printf("device: %s\n", p.deviceName); break; }
	}
	if (!phys) { fprintf(stderr, "no GPU device\nSTRESS_FAIL\n"); return 1; }

	uint32_t nq = 8;
	VkQueueFamilyProperties qf[8];
	vkGetPhysicalDeviceQueueFamilyProperties(phys, &nq, qf);
	uint32_t family = UINT32_MAX;
	for (uint32_t i = 0; i < nq; i++)
		if (qf[i].queueFlags & VK_QUEUE_COMPUTE_BIT) { family = i; break; }

	float prio = 1.0f;
	VkDeviceQueueCreateInfo qci = { .sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
		.queueFamilyIndex = family, .queueCount = 1, .pQueuePriorities = &prio };
	VkDeviceCreateInfo dci = { .sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
		.queueCreateInfoCount = 1, .pQueueCreateInfos = &qci };
	VkDevice dev;
	CHECK(vkCreateDevice(phys, &dci, NULL, &dev));
	VkQueue queue;
	vkGetDeviceQueue(dev, family, 0, &queue);

	/* One shared output buffer, as in the Metal test (storageModeShared). */
	VkDeviceSize bytes = (VkDeviceSize)W * H * 4;
	VkBufferCreateInfo bci = { .sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO, .size = bytes,
		.usage = VK_BUFFER_USAGE_STORAGE_BUFFER_BIT };
	VkBuffer buf;
	CHECK(vkCreateBuffer(dev, &bci, NULL, &buf));
	VkMemoryRequirements req;
	vkGetBufferMemoryRequirements(dev, buf, &req);
	VkPhysicalDeviceMemoryProperties mp;
	vkGetPhysicalDeviceMemoryProperties(phys, &mp);
	uint32_t type = UINT32_MAX;
	VkMemoryPropertyFlags want = VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT;
	for (uint32_t i = 0; i < mp.memoryTypeCount; i++)
		if ((req.memoryTypeBits & (1u << i)) && (mp.memoryTypes[i].propertyFlags & want) == want) { type = i; break; }
	VkMemoryAllocateInfo mai = { .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
		.allocationSize = req.size, .memoryTypeIndex = type };
	VkDeviceMemory mem;
	CHECK(vkAllocateMemory(dev, &mai, NULL, &mem));
	CHECK(vkBindBufferMemory(dev, buf, mem, 0));
	uint32_t *map;
	CHECK(vkMapMemory(dev, mem, 0, bytes, 0, (void **)&map));

	size_t spv_size;
	unsigned char *code = read_file(spv, &spv_size);
	VkShaderModuleCreateInfo smci = { .sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
		.codeSize = spv_size, .pCode = (const uint32_t *)code };
	VkShaderModule module;
	CHECK(vkCreateShaderModule(dev, &smci, NULL, &module));

	VkDescriptorSetLayoutBinding binding = { .binding = 0, .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
		.descriptorCount = 1, .stageFlags = VK_SHADER_STAGE_COMPUTE_BIT };
	VkDescriptorSetLayoutCreateInfo dslci = { .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		.bindingCount = 1, .pBindings = &binding };
	VkDescriptorSetLayout dsl;
	CHECK(vkCreateDescriptorSetLayout(dev, &dslci, NULL, &dsl));
	VkPushConstantRange pcr = { .stageFlags = VK_SHADER_STAGE_COMPUTE_BIT, .size = 4 };
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

	VkDescriptorPoolSize ps = { .type = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .descriptorCount = 1 };
	VkDescriptorPoolCreateInfo dpci = { .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
		.maxSets = 1, .poolSizeCount = 1, .pPoolSizes = &ps };
	VkDescriptorPool pool;
	CHECK(vkCreateDescriptorPool(dev, &dpci, NULL, &pool));
	VkDescriptorSetAllocateInfo dsai = { .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
		.descriptorPool = pool, .descriptorSetCount = 1, .pSetLayouts = &dsl };
	VkDescriptorSet set;
	CHECK(vkAllocateDescriptorSets(dev, &dsai, &set));
	VkDescriptorBufferInfo dbi = { .buffer = buf, .range = VK_WHOLE_SIZE };
	VkWriteDescriptorSet wds = { .sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = set,
		.descriptorCount = 1, .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .pBufferInfo = &dbi };
	vkUpdateDescriptorSets(dev, 1, &wds, 0, NULL);

	/* A ring of command buffers, so frames are in flight like the Metal command buffers. */
	VkCommandPoolCreateInfo cpi = { .sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
		.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT, .queueFamilyIndex = family };
	VkCommandPool cpool;
	CHECK(vkCreateCommandPool(dev, &cpi, NULL, &cpool));
	VkCommandBufferAllocateInfo cbai = { .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
		.commandPool = cpool, .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY, .commandBufferCount = RING };
	VkCommandBuffer cb[RING];
	CHECK(vkAllocateCommandBuffers(dev, &cbai, cb));
	VkFence fence[RING];
	VkFenceCreateInfo fci = { .sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO, .flags = VK_FENCE_CREATE_SIGNALED_BIT };
	for (int i = 0; i < RING; i++)
		CHECK(vkCreateFence(dev, &fci, NULL, &fence[i]));
	const uint64_t timeout = 10ull * 1000 * 1000 * 1000;

	long frames = 0, checks = 0, wrong = 0, last_frames = 0;
	double t0 = now(), last = t0, check_s = 0;
	double report_s = getenv("VK_STRESS_REPORT_S") ? atof(getenv("VK_STRESS_REPORT_S")) : 30;
	double pause_at = -1, pause_len = 0;
	if (getenv("VK_STRESS_PAUSE"))
		sscanf(getenv("VK_STRESS_PAUSE"), "%lf:%lf", &pause_at, &pause_len);
	while (now() - t0 < seconds) {
		if (pause_at >= 0 && now() - t0 >= pause_at) {
			CHECK(vkQueueWaitIdle(queue));
			printf("pause %.1f s at %.1f s (queue idle, same context)\n", pause_len, now() - t0);
			fflush(stdout);
			usleep((useconds_t)(pause_len * 1e6));
			t0 += pause_len;
			last += pause_len;
			pause_at = -1;
		}
		unsigned seed = (unsigned)frames * 2654435761u;
		int k = (int)(frames % RING);
		CHECK(vkWaitForFences(dev, 1, &fence[k], VK_TRUE, timeout));
		CHECK(vkResetFences(dev, 1, &fence[k]));
		CHECK(vkResetCommandBuffer(cb[k], 0));
		VkCommandBufferBeginInfo cbbi = { .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
			.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT };
		CHECK(vkBeginCommandBuffer(cb[k], &cbbi));
		vkCmdBindPipeline(cb[k], VK_PIPELINE_BIND_POINT_COMPUTE, pipeline);
		vkCmdBindDescriptorSets(cb[k], VK_PIPELINE_BIND_POINT_COMPUTE, layout, 0, 1, &set, 0, NULL);
		vkCmdPushConstants(cb[k], layout, VK_SHADER_STAGE_COMPUTE_BIT, 0, 4, &seed);
		vkCmdDispatch(cb[k], W / 16, H / 16, 1);
		VkMemoryBarrier mb = { .sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER,
			.srcAccessMask = VK_ACCESS_SHADER_WRITE_BIT,
			.dstAccessMask = VK_ACCESS_HOST_READ_BIT | VK_ACCESS_SHADER_WRITE_BIT };
		vkCmdPipelineBarrier(cb[k], VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,
			VK_PIPELINE_STAGE_HOST_BIT | VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, 0, 1, &mb, 0, NULL, 0, NULL);
		CHECK(vkEndCommandBuffer(cb[k]));
		VkSubmitInfo si = { .sType = VK_STRUCTURE_TYPE_SUBMIT_INFO, .commandBufferCount = 1, .pCommandBuffers = &cb[k] };
		CHECK(vkQueueSubmit(queue, 1, &si, fence[k]));
		frames++;
		if (check_every > 0 && frames % check_every == 0) {
			CHECK(vkWaitForFences(dev, 1, &fence[k], VK_TRUE, timeout));
			double c0 = now();
			checks++;
			long bad = 0;
			for (int y = 0; y < H; y += 7)
				for (int x = 0; x < W; x += 7)
					if (map[y * W + x] != cpu_value(x, y, seed))
						bad++;
			wrong += bad;
			if (bad)
				printf("frame %ld: %ld wrong samples\n", frames, bad);
			check_s += now() - c0;
		}
		if (now() - last >= report_s) {
			double step = now() - last;
			last = now();
			printf("%.0f s: %ld frames, %ld checks, %ld wrong, %.1f fps in this step\n", last - t0, frames, checks,
			       wrong, (frames - last_frames) / step);
			last_frames = frames;
			fflush(stdout);
		}
	}
	CHECK(vkQueueWaitIdle(queue));
	double t = now() - t0;
	printf("frames %ld in %.1f s (%.1f fps, %.2f Gpix-iter/s), checks %ld, wrong samples %ld\n",
	       frames, t, frames / t, frames * (double)W * H * ITERS / t / 1e9, checks, wrong);
	if (checks)
		printf("CPU check time %.2f ms per check (GPU idle meanwhile), every %ld frames\n",
		       check_s * 1000 / checks, check_every);
	printf("%s\n", wrong == 0 ? "STRESS_PASS" : "STRESS_FAIL");
	vkDestroyDevice(dev, NULL);
	vkDestroyInstance(instance, NULL);
	return wrong != 0;
}
