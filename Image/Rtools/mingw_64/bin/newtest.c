#include <stdio.h>
#include <math.h>

int main(void)
{
    int j;
    double d;

    for (j = -1; j > -10; j--)
    {
        d = powl(10, j);
        printf("10^j (j=%d), double=%.14a\n", j, d);
    }

    d = pow(10, -1);
    printf("10^-1, double=%.14a\n", d);
    d = pow(10, -2);
    printf("10^-2, double=%.14a\n", d);

    return 0;
}
