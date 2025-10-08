#define MINIAUDIO_IMPLEMENTATION
#include <stdint.h>
#include <string.h>
#include "miniaudio/miniaudio.h"

// Fixed audio format
#define NG_CHANNELS 2
#define NG_SAMPLE_RATE 48000
#define NG_SLOTS 16

typedef struct ng_slot {
	ma_bool32 initialized;
	ma_decoder decoder;
	ma_data_source_node node;
	ma_bool32 attached;
} ng_slot;

static ma_context g_ctx;
static ma_device g_device;
static ma_node_graph g_graph;
static ng_slot g_slots[NG_SLOTS];

static void data_callback(ma_device* pDevice, void* pOutput, const void* pInput, ma_uint32 frameCount) {
	(void)pInput; (void)pDevice;
	ma_node_graph_read_pcm_frames(&g_graph, pOutput, frameCount, NULL);
}

#ifdef _WIN32
#define NG_EXPORT __declspec(dllexport)
#else
#define NG_EXPORT __attribute__((visibility("default")))
#endif

NG_EXPORT int ng_init(void) {
	if (ma_context_init(NULL, 0, NULL, &g_ctx) != MA_SUCCESS) return -1;
	ma_node_graph_config nodeGraphConfig = ma_node_graph_config_init(NG_CHANNELS);
	if (ma_node_graph_init(&nodeGraphConfig, NULL, &g_graph) != MA_SUCCESS) return -2;

	for (int i = 0; i < NG_SLOTS; ++i) { g_slots[i].initialized = MA_FALSE; g_slots[i].attached = MA_FALSE; }

	ma_device_config deviceConfig = ma_device_config_init(ma_device_type_playback);
	deviceConfig.playback.format = ma_format_f32;
	deviceConfig.playback.channels = NG_CHANNELS;
	deviceConfig.sampleRate = NG_SAMPLE_RATE;
	deviceConfig.dataCallback = data_callback;
	deviceConfig.pUserData = NULL;
	if (ma_device_init(NULL, &deviceConfig, &g_device) != MA_SUCCESS) return -3;
	return 0;
}

NG_EXPORT int ng_start(void) {
	return (ma_device_start(&g_device) == MA_SUCCESS) ? 0 : -1;
}

NG_EXPORT void ng_stop(void) {
	ma_device_stop(&g_device);
}

NG_EXPORT void ng_shutdown(void) {
	for (int i = 0; i < NG_SLOTS; ++i) {
		if (g_slots[i].attached) {
			ma_data_source_node_uninit(&g_slots[i].node, NULL);
			g_slots[i].attached = MA_FALSE;
		}
		if (g_slots[i].initialized) {
			ma_decoder_uninit(&g_slots[i].decoder);
			g_slots[i].initialized = MA_FALSE;
		}
	}
	ma_node_graph_uninit(&g_graph, NULL);
	ma_device_uninit(&g_device);
	ma_context_uninit(&g_ctx);
}

NG_EXPORT int ng_load(int slotIndex, const char *path) {
	if (slotIndex < 0 || slotIndex >= NG_SLOTS) return -1;
	ng_slot *slot = &g_slots[slotIndex];
	if (slot->attached) { ma_data_source_node_uninit(&slot->node, NULL); slot->attached = MA_FALSE; }
	if (slot->initialized) { ma_decoder_uninit(&slot->decoder); slot->initialized = MA_FALSE; }

	ma_decoder_config decoderConfig = ma_decoder_config_init(ma_format_f32, NG_CHANNELS, NG_SAMPLE_RATE);
	if (ma_decoder_init_file(path, &decoderConfig, &slot->decoder) != MA_SUCCESS) return -2;
	slot->initialized = MA_TRUE;

	ma_data_source_node_config dataSourceNodeConfig = ma_data_source_node_config_init(&slot->decoder);
	if (ma_data_source_node_init(&g_graph, &dataSourceNodeConfig, NULL, &slot->node) != MA_SUCCESS) {
		ma_decoder_uninit(&slot->decoder);
		slot->initialized = MA_FALSE;
		return -3;
	}
	ma_node_attach_output_bus(&slot->node, 0, ma_node_graph_get_endpoint(&g_graph), 0);
	slot->attached = MA_TRUE;
	return 0;
}

NG_EXPORT int ng_trigger(int slotIndex) {
	if (slotIndex < 0 || slotIndex >= NG_SLOTS) return -1;
	ng_slot *slot = &g_slots[slotIndex];
	if (!slot->initialized) return -2;
	return (ma_decoder_seek_to_pcm_frame(&slot->decoder, 0) == MA_SUCCESS) ? 0 : -3;
}
