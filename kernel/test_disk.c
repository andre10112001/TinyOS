#define TEST_LOAD_ADDRESS 0X7000
#define LBA_33 33
#define SECTOR_COUNT 1

// External Assembly function prototype
// Assumes: int read_sectors_pio(unsigned long lba, unsigned char count, void *buffer);
extern int read_sectors_pio(unsigned long lba, unsigned char count, void *buffer);

void test_disk_read(void) {
    int result;
    
    // --- Step 1: Attempt the Disk Read ---
    result = read_sectors_pio(
        LBA_33,                       // LBA 33: Start of Data Area / Cluster 2
        (unsigned char)SECTOR_COUNT,  // 1 Sector
        (void *)TEST_LOAD_ADDRESS     // Destination: 0x7000
    );

    // --- Step 2: Check the result ---
    if (result == 0) {
        // Success!
        // Print a success message (you'll need a VRAM print function like print_hello)
        // print_success_message("Successfully loaded LBA 33 into 0x7000.");

        // Optionally, check the first few bytes of the buffer for validity
        unsigned char *buffer = (unsigned char *)TEST_LOAD_ADDRESS;
        
        // This is where the file data is!
        // Example: If LBA 33 contains KERNEL.BIN, the start bytes are there.
        
    } else {
        // Failure!
        // print_error_message("Disk read failed with code: %d", result);
        
        // Loop indefinitely on error
        for (;;);
    }
}