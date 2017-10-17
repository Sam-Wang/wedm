%% Initialization

format compact;
warning off;
close all;
clear all;
clc;

%% Tweakable Parameters

T_mach = 200e-6;  % Machining time period

I_ref = 10;
V_ref = 80;

Vd_val = 110;
r_val = 1;
f_sw = 50e3;
fSampling = f_sw;

rl1_val = 0.0002;
rl2_val = 0.0001;
rc2_val = 0.0001;

i1_ripple = 0.01;
v2_ripple = 0.01;


% Working Values when PM was being calculated wromg are
%a2_vs = 1e-8;
%pm_des_vs = 30;

% If -1/(r_val*c2_val) present in vs modelling
%pm_des_vs = 60;
%a2_vs = 0.5e-7;
%wm2=1;

% Otherwise
pm_des_vs = 60;
a2_vs = 1e-8;
wm2=1;

Ron = 32e-3;
Vf = 1.3;

%% MACHINING TIMES

f_mach = 1 / T_mach;
duty = 10;        % duty cycle in percentage
t2 = duty * T_mach / 100;  % time delay
t1 = t2 * 30/100; % IGNITION delay assumed to be 10% of the total spark duration
duty_inv = 100 - duty;   % Duty for control signal of ignition or dead time switch
duty_load = (t2-t1)/T_mach*100;  % Duty for turning ON load
delay_load = t1;
delayVC = 0; % Delay between start of vsrc and csrc

%% INDUCTOR FOR SINGLE QUADRANT CHOPPER

Vo1 = I_ref * r_val;
delta_i1 = i1_ripple * I_ref;
l1_val = Vo1*(Vd_val-Vo1)/(delta_i1*f_sw*Vd_val)

%% INDUCTOR FOR TWO QUADRANT CHOPPER

l2_val = 10*2.5*r_val*(Vd_val-V_ref)/(f_sw*Vd_val)
% 10 times original value because the current through Q2 was high

%% CAPACITOR FOR TWO QUADRANT CHOPPER

c2_val = (1-V_ref/Vd_val)/(8*v2_ripple*l2_val*f_sw^2)

%% VOLTAGE SOURCE MODEL

%% Declare Symbolic Variables
syms rc2 c2 rl2 l2 Vd d2 s;

%% State Space Model

% Power Supply As described in Paper
% Switch ON Time
A1 = [-(rl2+rc2)/l2 -1/l2;
      1/c2 0]; % A1(2,2) = -1/(r_val*c2_val) is more correct
B1 = [1/l2; 0];
C1 = [rc2_val 1];

% Switch OFF Time
A2 = A1;
B2 = [0; 0];
C2 = C1;

% Time Averaging
A = simplify(d2*A1+(1-d2)*A2);
B = simplify(d2*B1+(1-d2)*B2);
C = simplify(d2*C1+(1-d2)*C2);

X = [V_ref/r_val ;V_ref];

% Small Signal Transfer Function
fprintf('Small Signal Transfer Function of Uncomepensated System\n')
vohat_dhat = simplify(C*inv(s*eye(2)-A)*((A1 - A2)*X+(B1-B2)*Vd)+(C1-C2)*X);
G_VS = syms2tf(subs(vohat_dhat, [rc2, c2, rl2, l2, Vd],...
        [rc2_val, c2_val, rl2_val, l2_val, Vd_val]))

% Discrete Time Transfer Function
discreteG_VS = c2d(G_VS, 1/fSampling, 'tustin')

% Gain Margin, Phase Margin, Bode Plot
[Gm,Pm,Wgm,Wpm] = margin(G_VS);
fprintf('Gain Margin = %e\n', Gm)
fprintf('Phase Margin = %e\n', Pm)
fprintf('Phase Crossover Frequency = %e\n', Wgm)
fprintf('Gain Crossover Frequency = %e\n\n', Wpm)

figure(1)
margin(G_VS)

%% VOLTAGE SOURCE CONTROLLER

%% Declare Symbolic Variables
syms a1 T1 a2 T2;

%% Compensator Design

wcross2 = 2*pi*f_sw/3.25;
% Lead Compensator Design
Gc1 = (1+a1*T1*s)/(1+T1*s);
[~, Ph] = bode(G_VS, wcross2);
phi_m = pm_des_vs-(180+Ph);

a1_val = (1+sind(phi_m))/(1-sind(phi_m));
T1_val = 1/(wcross2*sqrt(a1_val));
Gc1 = syms2tf(subs(Gc1, [a1, T1], [a1_val, T1_val]));

% Lag Compensator Design
Gc2 = (1+a2*T2*s)/(a2*(1+T2*s));

T2_val = 1/(wm2*sqrt(a2_vs));
Gc2 = syms2tf(subs(Gc2, [a2, T2], [a2_vs, T2_val]));

% Balancing Loop Gain
Ac = 1/(evalfr(G_VS, wcross2)*evalfr(Gc1, wcross2)*evalfr(Gc2, wcross2));
fprintf('Compensator Transfer Function\n')
Gc = Ac*Gc1*Gc2;

% Gain Margin, Phase Margin, Bode Plot of Compensated System
[Gm,Pm,Wgm,Wpm] = margin(Gc*G_VS);
fprintf('New Gain Margin = %e\n', Gm)
fprintf('New Phase Margin = %e\n', Pm)
fprintf('New Phase Crossover Frequency = %e\n', Wgm)
fprintf('New Gain Crossover Frequency = %e\n\n', Wpm)

figure(3)
margin(Gc*G_VS)
[num_c2, den_c2] = tfdata(Gc);

%% CURRENT SOURCE MODEL

%% Declare Symbolic Variables
syms r rl1 l1 Vd d2 s;

%% State Space Model

% Power Supply As described in Paper
% Switch ON Time
A1 = -(rl1+r)/l1;
B1 = 1/l1;
C1 = 1;

% Switch OFF Time
A2 = A1;
B2 = 0;
C2 = C1;

% Time Averaging
A = simplify(d2*A1+(1-d2)*A2);
B = simplify(d2*B1+(1-d2)*B2);
C = simplify(d2*C1+(1-d2)*C2);

X = I_ref;

% Small Signal Transfer Function
vohat_dhat = simplify(C*inv(s*eye(1)-A)*((A1 - A2)*X+(B1-B2)*Vd)+(C1-C2)*X);
fprintf('Small Signal Transfer Function of Uncomepensated System\n')
G_CS = syms2tf(subs(vohat_dhat, [r, rl1, l1, Vd],...
        [r_val, rl1_val, l1_val, Vd_val]))

% Discrete Time Transfer Function
discreteG_CS = c2d(G_CS, 1/fSampling, 'tustin')

% Gain Margin, Phase Margin, Bode Plot
[Gm,Pm,Wgm,Wpm] = margin(G_CS);
fprintf('Gain Margin = %e\n', Gm)
fprintf('Phase Margin = %e\n', Pm)
fprintf('Phase Crossover Frequency = %e\n', Wgm)
fprintf('Gain Crossover Frequency = %e\n\n', Wpm)

figure(2)
margin(G_CS)

%% CURRENT SOURCE CONTROLLER
%% Declare Symbolic Variables
syms a1 T1 a2 T2;

%% Compensator Design

% Parameters
%pm_des = 160; % Desired Phase Margin
a2_val = 1e-10;

% Lead Compensator Design
wcross = wcross2;
Gc1 = (1+a1*T1*s)/(1+T1*s);
[Mag, Ph] = bode(G_CS, wcross2);
phi_m = pm_des_vs-(180+Ph)
a1_val = (1+sind(phi_m))/(1-sind(phi_m));
T1_val = 1/(wcross*sqrt(a1_val))
Gc1 = syms2tf(subs(Gc1, [a1, T1], [a1_val, T1_val]))

% Balancing Loop Gain
Ac = 1/(evalfr(G_CS, wcross)*evalfr(Gc1, wcross));
fprintf('Compensator Transfer Function\n')
Gc = Ac*Gc1

% Gain Margin, Phase Margin, Bode Plot of Compensated System
[Gm,Pm,Wgm,Wpm] = margin(Gc*G_CS);
fprintf('New Gain Margin = %e\n', Gm)
fprintf('New Phase Margin = %e\n', Pm)
fprintf('New Phase Crossover Frequency = %e\n', Wgm)
fprintf('New Gain Crossover Frequency = %e\n\n', Wpm)

figure(4)
margin(Gc*G_CS)
Gc = tf(1);
[num_c1, den_c1] = tfdata(Gc);


%% SNUBBER DESIGN OF Qd

Rs = V_ref / I_ref;
Ton = (T_mach - t2);
L = l1_val + l2_val; % Max worst case inductance across Qd
Cs_min = L * I_ref^2 / V_ref^2;
Cs_max = Ton / (10 * Rs);
Cs = (Cs_min + Cs_max) / 2;

%% SNUBBER DESIGN OF Q2

Rs2 = 110 / 160;
Ton = (0.432 - 0.42)*1e-3;
L = l1_val + l2_val; % Max worst case inductance across Qd
Cs_min = L * 160^2 / 110^2;
Cs_max = Ton / (10 * Rs);
Cs2 = (Cs_min + Cs_max) / 2;

%% END