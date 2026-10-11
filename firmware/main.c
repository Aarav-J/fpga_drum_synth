#define LED_REG (*(volatile unsigned int*)0x10000000)
static void delay(volatile unsigned int count) { 
    while (count--) {}
}

int main(void) { 
    unsigned int counter = 0; 
    while (1) {
        LED_REG = counter; 
        counter++; 
        delay(500000);

    }
    return 0; 
}
